const std = @import("std");
const todo_mod = @import("todo.zig");

pub const StatusFilter = enum { open, done, all };

pub const Filter = struct {
    status: StatusFilter = .open,
    priority: ?todo_mod.Priority = null,
    /// All listed tags must be present (AND).
    tags: []const []const u8 = &.{},
    /// If set, only open todos with due_at < now.
    overdue_before: ?i64 = null,
};

pub fn matchesStatus(item: todo_mod.Todo, filter: StatusFilter) bool {
    return switch (filter) {
        .all => true,
        .open => item.status == .open,
        .done => item.status == .done,
    };
}

pub fn matches(item: todo_mod.Todo, filter: Filter) bool {
    if (!matchesStatus(item, filter.status)) return false;
    if (filter.priority) |p| {
        if (item.priority != p) return false;
    }
    for (filter.tags) |tag| {
        if (!item.hasTag(tag)) return false;
    }
    if (filter.overdue_before) |now| {
        if (!item.isOverdue(now)) return false;
    }
    return true;
}

test "combined filter and overdue" {
    const gpa = std.testing.allocator;
    var item = try todo_mod.create(gpa, 1, "a", 0, .{
        .priority = .high,
        .tags = &.{ "docs", "cli" },
        .due_at = 50,
    });
    defer item.deinit(gpa);

    try std.testing.expect(matches(item, .{ .status = .open, .priority = .high, .tags = &.{"docs"} }));
    try std.testing.expect(matches(item, .{ .status = .open, .overdue_before = 100 }));
    try std.testing.expect(!matches(item, .{ .status = .open, .overdue_before = 10 }));
}
