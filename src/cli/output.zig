const std = @import("std");
const Io = std.Io;

const version = @import("../version.zig").version;
const domain_todo = @import("../domain/todo.zig");
const domain_list = @import("../domain/list.zig");
const filter_mod = @import("../domain/filter.zig");

pub fn printHelp(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        \\zig-todo — lightweight local todo CLI
        \\
        \\Usage:
        \\  zig-todo <command> [flags] [args]
        \\
        \\Commands:
        \\  add <text>              Add a todo
        \\  list, ls                List todos (default: open)
        \\  done <id>               Mark todo done
        \\  rm, delete <id>         Delete a todo
        \\  version                 Print version
        \\  help                    Show this help
        \\
        \\Flags:
        \\  --status open|done|all  Filter for list (default: open)
        \\  --data-dir <path>       Override data directory
        \\  -h, --help              Show this help
        \\  -V, --version           Print version
        \\
        \\Examples:
        \\  zig-todo add "first task"
        \\  zig-todo list --status all
        \\  zig-todo done 1
        \\  zig-todo rm 2
        \\
    );
}

pub fn printVersion(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("zig-todo {s}\n", .{version});
}

pub fn printUsageError(writer: *Io.Writer, message: []const u8) Io.Writer.Error!void {
    try writer.print("error: {s}\n", .{message});
    try writer.writeAll("Try 'zig-todo --help' for usage.\n");
}

pub fn printError(writer: *Io.Writer, message: []const u8) Io.Writer.Error!void {
    try writer.print("error: {s}\n", .{message});
}

pub fn printAdded(writer: *Io.Writer, id: u64, text: []const u8) Io.Writer.Error!void {
    try writer.print("Added #{d}: {s}\n", .{ id, text });
}

pub fn printDone(writer: *Io.Writer, id: u64) Io.Writer.Error!void {
    try writer.print("Done #{d}\n", .{id});
}

pub fn printRemoved(writer: *Io.Writer, id: u64) Io.Writer.Error!void {
    try writer.print("Removed #{d}\n", .{id});
}

pub fn printTodoList(
    writer: *Io.Writer,
    list: *const domain_list.TodoList,
    status: filter_mod.StatusFilter,
) Io.Writer.Error!void {
    var shown: usize = 0;
    for (list.items.items) |item| {
        if (!filter_mod.matchesStatus(item, status)) continue;
        if (shown == 0) {
            try writer.writeAll("ID  STATUS  TEXT\n");
        }
        shown += 1;
        try writer.print("{d:<3} {s:<7} {s}\n", .{
            item.id,
            statusString(item.status),
            item.text,
        });
    }
    if (shown == 0) {
        if (list.items.items.len == 0) {
            try writer.writeAll("No todos. Add one with: zig-todo add \"...\"\n");
        } else {
            try writer.writeAll("No todos matched.\n");
        }
    }
}

fn statusString(s: domain_todo.Status) []const u8 {
    return switch (s) {
        .open => "open",
        .done => "done",
    };
}
