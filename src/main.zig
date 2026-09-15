const std = @import("std");
const Io = std.Io;

const zig_todo = @import("zig_todo");
const cli = zig_todo.cli;
const app = zig_todo.app;
const storage = zig_todo.storage;
const filter_mod = zig_todo.domain.filter;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const parsed = cli.args.parse(args);
    const code: u8 = switch (parsed.command) {
        .help => blk: {
            try cli.output.printHelp(stdout);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .version => blk: {
            try cli.output.printVersion(stdout);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .usage => |msg| blk: {
            try cli.output.printUsageError(stderr, msg);
            try stderr.flush();
            break :blk cli.exit_codes.usage_error;
        },
        .unknown => |name| blk: {
            try cli.output.printUsageError(stderr, try std.fmt.allocPrint(
                arena,
                "unknown command '{s}'",
                .{name},
            ));
            try stderr.flush();
            break :blk cli.exit_codes.usage_error;
        },
        else => try runStoreCommand(init, parsed, stdout, stderr, gpa, io),
    };

    if (code != cli.exit_codes.success) {
        std.process.exit(code);
    }
}

fn runStoreCommand(
    init: std.process.Init,
    parsed: cli.commands.Parsed,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    gpa: std.mem.Allocator,
    io: Io,
) !u8 {
    const data_dir = try storage.paths.resolveDataDir(
        gpa,
        init.minimal.environ,
        parsed.data_dir,
    );
    defer gpa.free(data_dir);

    var store = try storage.store.JsonFileStore.init(gpa, io, data_dir);
    defer store.deinit();

    const now = app.now(io);

    return switch (parsed.command) {
        .add => |a| blk: {
            const id = app.add(&store, a.text, now, .{
                .priority = a.priority,
                .tags = a.tags.slice(),
            }) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (parsed.json) {
                var list = app.loadAll(&store) catch |err| {
                    break :blk try mapError(stderr, err);
                };
                defer list.deinit();
                const item = list.findById(id) orelse {
                    break :blk try mapError(stderr, error.NotFound);
                };
                cli.output.printTodoJson(gpa, stdout, item.*) catch |err| {
                    break :blk try mapError(stderr, err);
                };
            } else if (!parsed.quiet) {
                try cli.output.printAdded(stdout, id, a.text);
            }
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .list => |l| blk: {
            var list = app.loadAll(&store) catch |err| {
                break :blk try mapError(stderr, err);
            };
            defer list.deinit();
            const filter: filter_mod.Filter = .{
                .status = l.status,
                .priority = l.priority,
                .tags = l.tags.slice(),
            };
            if (parsed.json) {
                cli.output.printTodoListJson(gpa, stdout, &list, filter) catch |err| {
                    break :blk try mapError(stderr, err);
                };
            } else {
                try cli.output.printTodoList(stdout, &list, filter);
            }
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .show => |s| blk: {
            var list = app.loadAll(&store) catch |err| {
                break :blk try mapError(stderr, err);
            };
            defer list.deinit();
            const item = list.findById(s.id) orelse {
                break :blk try mapError(stderr, error.NotFound);
            };
            if (parsed.json) {
                cli.output.printTodoJson(gpa, stdout, item.*) catch |err| {
                    break :blk try mapError(stderr, err);
                };
            } else {
                try cli.output.printTodoDetail(stdout, item.*);
            }
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .done => |d| blk: {
            app.markDone(&store, d.id, now) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (!parsed.quiet and !parsed.json) try cli.output.printDone(stdout, d.id);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .undone => |d| blk: {
            app.markOpen(&store, d.id, now) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (!parsed.quiet and !parsed.json) try cli.output.printUndone(stdout, d.id);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .edit => |e| blk: {
            const patch: app.EditPatch = .{
                .text = e.text,
                .priority = e.priority,
                .tags = if (e.tags) |tb| tb.slice() else null,
            };
            app.edit(&store, e.id, patch, now) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (parsed.json) {
                var list = app.loadAll(&store) catch |err| {
                    break :blk try mapError(stderr, err);
                };
                defer list.deinit();
                const item = list.findById(e.id) orelse {
                    break :blk try mapError(stderr, error.NotFound);
                };
                cli.output.printTodoJson(gpa, stdout, item.*) catch |err| {
                    break :blk try mapError(stderr, err);
                };
            } else if (!parsed.quiet) {
                try cli.output.printEdited(stdout, e.id);
            }
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .rm => |r| blk: {
            app.remove(&store, r.id) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (!parsed.quiet and !parsed.json) try cli.output.printRemoved(stdout, r.id);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        .clear => blk: {
            const n = app.clearDone(&store) catch |err| {
                break :blk try mapError(stderr, err);
            };
            if (!parsed.quiet and !parsed.json) try cli.output.printCleared(stdout, n);
            try stdout.flush();
            break :blk cli.exit_codes.success;
        },
        else => unreachable,
    };
}

fn mapError(stderr: *Io.Writer, err: anyerror) !u8 {
    const msg: []const u8 = switch (err) {
        error.NotFound => "todo not found",
        error.EmptyText => "todo text must not be empty",
        error.TextTooLong => "todo text is too long",
        error.EmptyTag => "tag must not be empty",
        error.TagTooLong => "tag is too long",
        error.TooManyTags => "too many tags",
        error.CorruptData => "todos.json is corrupt",
        error.UnsupportedVersion => "unsupported todos.json version",
        error.OutOfMemory => "out of memory",
        error.IoError => "filesystem error",
        else => "unexpected error",
    };
    try cli.output.printError(stderr, msg);
    try stderr.flush();
    return switch (err) {
        error.NotFound,
        error.EmptyText,
        error.TextTooLong,
        error.EmptyTag,
        error.TagTooLong,
        error.TooManyTags,
        => cli.exit_codes.general_error,
        error.CorruptData,
        error.UnsupportedVersion,
        error.OutOfMemory,
        error.IoError,
        => cli.exit_codes.internal_error,
        else => cli.exit_codes.internal_error,
    };
}
