const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const version = @import("../version.zig").version;
const domain_todo = @import("../domain/todo.zig");
const domain_list = @import("../domain/list.zig");
const filter_mod = @import("../domain/filter.zig");

pub fn printHelp(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        \\zig-todo — lightweight local todo CLI
        \\
        \\Usage:
        \\  zig-todo [global flags] <command> [flags] [args]
        \\
        \\Commands:
        \\  add "<text>" [-p pri] [-t tag]...   Add a todo
        \\  list, ls [filters]                  List todos (default: open)
        \\  show <id>                           Show one todo
        \\  edit <id> [-d text] [-p pri] [-t tag]...
        \\  done <id>                           Mark done
        \\  undone <id>                         Mark open
        \\  rm, delete <id>                     Delete
        \\  clear --done                        Remove completed todos
        \\  version                             Print version
        \\  help                                Show this help
        \\
        \\List filters:
        \\  --status open|done|all
        \\  --priority|-p low|medium|high
        \\  --tag|-t <tag>                      (repeatable, AND)
        \\
        \\Global flags:
        \\  --json                 JSON output
        \\  -q, --quiet            Less human output
        \\  --data-dir <path>      Override data directory
        \\  -h, --help             Show this help
        \\  -V, --version          Print version
        \\
        \\Examples:
        \\  zig-todo add "写文档" -p high -t docs -t cli
        \\  zig-todo list --priority high --tag docs
        \\  zig-todo edit 1 -d "写产品与架构文档"
        \\  zig-todo list --json
        \\  zig-todo clear --done
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

pub fn printUndone(writer: *Io.Writer, id: u64) Io.Writer.Error!void {
    try writer.print("Undone #{d}\n", .{id});
}

pub fn printRemoved(writer: *Io.Writer, id: u64) Io.Writer.Error!void {
    try writer.print("Removed #{d}\n", .{id});
}

pub fn printEdited(writer: *Io.Writer, id: u64) Io.Writer.Error!void {
    try writer.print("Updated #{d}\n", .{id});
}

pub fn printCleared(writer: *Io.Writer, count: usize) Io.Writer.Error!void {
    try writer.print("Cleared {d} done todo(s)\n", .{count});
}

pub fn printTodoList(
    writer: *Io.Writer,
    list: *const domain_list.TodoList,
    filter: filter_mod.Filter,
) Io.Writer.Error!void {
    var shown: usize = 0;
    for (list.items.items) |item| {
        if (!filter_mod.matches(item, filter)) continue;
        if (shown == 0) {
            try writer.writeAll("ID  PRI   STATUS  TAGS        TEXT\n");
        }
        shown += 1;
        try writer.print("{d:<3} {s:<5} {s:<7} ", .{
            item.id,
            domain_todo.priorityString(item.priority),
            statusString(item.status),
        });
        try writeTagsPadded(writer, item.tags, 11);
        try writer.print(" {s}\n", .{item.text});
    }
    if (shown == 0) {
        if (list.items.items.len == 0) {
            try writer.writeAll("No todos. Add one with: zig-todo add \"...\"\n");
        } else {
            try writer.writeAll("No todos matched.\n");
        }
    }
}

pub fn printTodoDetail(writer: *Io.Writer, item: domain_todo.Todo) Io.Writer.Error!void {
    try writer.print("id:           {d}\n", .{item.id});
    try writer.print("status:       {s}\n", .{statusString(item.status)});
    try writer.print("priority:     {s}\n", .{domain_todo.priorityJsonString(item.priority)});
    try writer.writeAll("tags:         ");
    try writeTagsPlain(writer, item.tags);
    try writer.writeAll("\n");
    try writer.print("created_at:   {d}\n", .{item.created_at});
    try writer.print("updated_at:   {d}\n", .{item.updated_at});
    if (item.completed_at) |c| {
        try writer.print("completed_at: {d}\n", .{c});
    } else {
        try writer.writeAll("completed_at: null\n");
    }
    try writer.print("text:         {s}\n", .{item.text});
}

pub fn printTodoListJson(
    allocator: Allocator,
    writer: *Io.Writer,
    list: *const domain_list.TodoList,
    filter: filter_mod.Filter,
) !void {
    var first = true;
    try writer.writeAll("[");
    for (list.items.items) |item| {
        if (!filter_mod.matches(item, filter)) continue;
        if (!first) try writer.writeAll(",");
        first = false;
        try writeTodoJson(allocator, writer, item);
    }
    try writer.writeAll("]\n");
}

pub fn printTodoJson(allocator: Allocator, writer: *Io.Writer, item: domain_todo.Todo) !void {
    try writeTodoJson(allocator, writer, item);
    try writer.writeAll("\n");
}

fn writeTodoJson(allocator: Allocator, writer: *Io.Writer, item: domain_todo.Todo) !void {
    const view = JsonTodo{
        .id = item.id,
        .text = item.text,
        .status = item.status,
        .priority = item.priority,
        .tags = item.tags,
        .created_at = item.created_at,
        .updated_at = item.updated_at,
        .completed_at = item.completed_at,
    };
    const bytes = try std.json.Stringify.valueAlloc(allocator, view, .{});
    defer allocator.free(bytes);
    try writer.writeAll(bytes);
}

const JsonTodo = struct {
    id: u64,
    text: []const u8,
    status: domain_todo.Status,
    priority: domain_todo.Priority,
    tags: []const []const u8,
    created_at: i64,
    updated_at: i64,
    completed_at: ?i64,
};

fn statusString(s: domain_todo.Status) []const u8 {
    return switch (s) {
        .open => "open",
        .done => "done",
    };
}

fn writeTagsPlain(writer: *Io.Writer, tags: []const []const u8) Io.Writer.Error!void {
    if (tags.len == 0) {
        try writer.writeAll("-");
        return;
    }
    for (tags, 0..) |tag, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.writeAll(tag);
    }
}

fn writeTagsPadded(writer: *Io.Writer, tags: []const []const u8, width: usize) Io.Writer.Error!void {
    var count: usize = 0;
    if (tags.len == 0) {
        try writer.writeAll("-");
        count = 1;
    } else {
        for (tags, 0..) |tag, i| {
            if (i != 0) {
                try writer.writeByte(',');
                count += 1;
            }
            try writer.writeAll(tag);
            count += tag.len;
        }
    }
    while (count < width) : (count += 1) {
        try writer.writeByte(' ');
    }
}
