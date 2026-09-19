const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const version = @import("../version.zig").version;
const domain_todo = @import("../domain/todo.zig");
const domain_list = @import("../domain/list.zig");
const filter_mod = @import("../domain/filter.zig");
const date_util = @import("../util/date.zig");

pub fn printHelp(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        \\zig-todo — lightweight local todo CLI
        \\
        \\Usage:
        \\  zig-todo [global flags] <command> [flags] [args]
        \\
        \\Commands:
        \\  add "<text>" [-p pri] [-t tag]... [--due YYYY-MM-DD]
        \\  list, ls [filters]                  List todos (default: open)
        \\  show <id>                           Show one todo
        \\  edit <id> [-d text] [-p pri] [-t tag]... [--due DATE|none]
        \\  done <id>                           Mark done
        \\  undone <id>                         Mark open
        \\  rm, delete <id>                     Delete
        \\  clear --done                        Remove completed todos
        \\  archive --done                      Move completed to archive.json
        \\  export [path]                       Export JSON array (stdout if no path)
        \\  import <path>                       Import JSON array or document
        \\  version                             Print version
        \\  help                                Show this help
        \\
        \\List filters:
        \\  --all / --done / --open             Status filter
        \\  --priority|-p low|medium|high
        \\  --tag|-t <tag>                      (repeatable, AND)
        \\  --overdue                           Open todos past due date
        \\
        \\Global flags:
        \\  --json                 JSON output
        \\  -q, --quiet            Less human output
        \\  --data-dir <path>      Override data directory
        \\  -h, --help             Show this help
        \\  -V, --version          Print version
        \\
        \\Data file:
        \\  macOS: ~/Library/Application Support/zig-todo/todos.json
        \\  Linux: ~/.local/share/zig-todo/todos.json
        \\  Windows: %APPDATA%\zig-todo\todos.json
        \\  Override with --data-dir or ZIG_TODO_DATA_DIR
        \\
        \\Examples:
        \\  zig-todo add "写文档" -p high -t docs --due 2026-12-31
        \\  zig-todo list --overdue
        \\  zig-todo export backup.json
        \\  zig-todo import backup.json
        \\  zig-todo archive --done
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

pub fn printArchived(writer: *Io.Writer, count: usize) Io.Writer.Error!void {
    try writer.print("Archived {d} done todo(s)\n", .{count});
}

pub fn printImported(writer: *Io.Writer, count: usize) Io.Writer.Error!void {
    try writer.print("Imported {d} todo(s)\n", .{count});
}

pub fn printExported(writer: *Io.Writer, path: []const u8) Io.Writer.Error!void {
    try writer.print("Exported to {s}\n", .{path});
}

pub fn printTodoList(
    writer: *Io.Writer,
    list: *const domain_list.TodoList,
    filter: filter_mod.Filter,
) Io.Writer.Error!void {
    const id_w: usize = 4;
    const pri_w: usize = 5;
    const status_w: usize = 7;
    const due_w: usize = 10;
    const tags_w: usize = 12;
    var matched: usize = 0;

    for (list.items.items) |item| {
        if (!filter_mod.matches(item, filter)) continue;
        matched += 1;
    }

    if (matched == 0) {
        if (list.items.items.len == 0) {
            try writer.writeAll("No todos yet.\n");
            try writer.writeAll("Add one with: zig-todo add \"your task\"\n");
        } else {
            try writer.writeAll("No todos matched the current filters.\n");
            try writer.writeAll("Try: zig-todo list --all\n");
        }
        return;
    }

    try padWrite(writer, "ID", id_w);
    try writer.writeAll("  ");
    try padWrite(writer, "PRI", pri_w);
    try writer.writeAll("  ");
    try padWrite(writer, "STATUS", status_w);
    try writer.writeAll("  ");
    try padWrite(writer, "DUE", due_w);
    try writer.writeAll("  ");
    try padWrite(writer, "TAGS", tags_w);
    try writer.writeAll("  TEXT\n");

    for (list.items.items) |item| {
        if (!filter_mod.matches(item, filter)) continue;
        try padWriteInt(writer, item.id, id_w);
        try writer.writeAll("  ");
        try padWrite(writer, domain_todo.priorityString(item.priority), pri_w);
        try writer.writeAll("  ");
        try padWrite(writer, statusString(item.status), status_w);
        try writer.writeAll("  ");
        try writeDuePadded(writer, item.due_at, due_w);
        try writer.writeAll("  ");
        try writeTagsPadded(writer, item.tags, tags_w);
        try writer.print("  {s}\n", .{item.text});
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
        try writer.writeAll("completed_at: -\n");
    }
    if (item.due_at) |d| {
        var buf: [16]u8 = undefined;
        try writer.print("due_at:       {s} ({d})\n", .{ date_util.formatDueDate(d, &buf), d });
    } else {
        try writer.writeAll("due_at:       -\n");
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
        .due_at = item.due_at,
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
    due_at: ?i64 = null,
};

fn statusString(s: domain_todo.Status) []const u8 {
    return switch (s) {
        .open => "open",
        .done => "done",
    };
}

fn writeDuePadded(writer: *Io.Writer, due_at: ?i64, width: usize) Io.Writer.Error!void {
    if (due_at) |ts| {
        var buf: [16]u8 = undefined;
        const text = date_util.formatDueDate(ts, &buf);
        try padWrite(writer, text, width);
    } else {
        try padWrite(writer, "-", width);
    }
}

fn padWrite(writer: *Io.Writer, text: []const u8, width: usize) Io.Writer.Error!void {
    try writer.writeAll(text);
    var i: usize = text.len;
    while (i < width) : (i += 1) try writer.writeByte(' ');
}

fn padWriteInt(writer: *Io.Writer, n: u64, width: usize) Io.Writer.Error!void {
    var buf: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
    try padWrite(writer, text, width);
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
