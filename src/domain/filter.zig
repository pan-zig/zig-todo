const todo_mod = @import("todo.zig");

pub const StatusFilter = enum { open, done, all };

pub fn matchesStatus(item: todo_mod.Todo, filter: StatusFilter) bool {
    return switch (filter) {
        .all => true,
        .open => item.status == .open,
        .done => item.status == .done,
    };
}

test "status filter" {
    const std = @import("std");
    const gpa = std.testing.allocator;
    var open_item = try todo_mod.create(gpa, 1, "a", 0);
    defer open_item.deinit(gpa);
    var done_item = try todo_mod.create(gpa, 2, "b", 0);
    defer done_item.deinit(gpa);
    todo_mod.markDone(&done_item, 1);

    try std.testing.expect(matchesStatus(open_item, .open));
    try std.testing.expect(!matchesStatus(done_item, .open));
    try std.testing.expect(matchesStatus(done_item, .done));
    try std.testing.expect(matchesStatus(open_item, .all));
}
