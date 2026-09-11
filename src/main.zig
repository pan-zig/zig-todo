const std = @import("std");
const Io = std.Io;

const zig_todo = @import("zig_todo");
const cli = zig_todo.cli;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const command = cli.args.parse(args);
    const code: u8 = switch (command) {
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
        .unknown => |name| blk: {
            try cli.output.printUsageError(stderr, try std.fmt.allocPrint(
                arena,
                "unknown command '{s}'",
                .{name},
            ));
            try stderr.flush();
            break :blk cli.exit_codes.usage_error;
        },
    };

    if (code != cli.exit_codes.success) {
        std.process.exit(code);
    }
}
