const std = @import("std");
const Allocator = std.mem.Allocator;

const todo_mod = @import("todo.zig");
const id_mod = @import("id.zig");
const filter_mod = @import("filter.zig");

pub const Todo = todo_mod.Todo;
pub const StatusFilter = filter_mod.StatusFilter;

pub const TodoList = struct {
    allocator: Allocator,
    next_id: u64,
    items: std.ArrayList(Todo),

    pub fn init(allocator: Allocator) TodoList {
        return .{
            .allocator = allocator,
            .next_id = 1,
            .items = .empty,
        };
    }

    pub fn deinit(self: *TodoList) void {
        for (self.items.items) |item| item.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    pub fn healIds(self: *TodoList) void {
        var max_id: u64 = 0;
        for (self.items.items) |item| {
            if (item.id > max_id) max_id = item.id;
        }
        self.next_id = id_mod.healNextId(self.next_id, max_id);
    }

    pub fn addNew(self: *TodoList, text: []const u8, now: i64) todo_mod.CreateError!Todo {
        const id = self.next_id;
        const item = try todo_mod.create(self.allocator, id, text, now);
        errdefer item.deinit(self.allocator);
        try self.items.append(self.allocator, item);
        self.next_id = id + 1;
        return item;
    }

    pub fn findIndex(self: *const TodoList, id: u64) ?usize {
        for (self.items.items, 0..) |item, i| {
            if (item.id == id) return i;
        }
        return null;
    }

    pub fn findById(self: *TodoList, id: u64) ?*Todo {
        const idx = self.findIndex(id) orelse return null;
        return &self.items.items[idx];
    }

    pub fn markDone(self: *TodoList, id: u64, now: i64) error{NotFound}!void {
        const item = self.findById(id) orelse return error.NotFound;
        todo_mod.markDone(item, now);
    }

    pub fn removeById(self: *TodoList, id: u64) error{NotFound}!Todo {
        const idx = self.findIndex(id) orelse return error.NotFound;
        return self.items.orderedRemove(idx);
    }

    pub fn filtered(self: *const TodoList, status: StatusFilter, out: *std.ArrayList(*const Todo)) Allocator.Error!void {
        out.clearRetainingCapacity();
        for (self.items.items) |*item| {
            if (filter_mod.matchesStatus(item.*, status)) {
                try out.append(self.allocator, item);
            }
        }
    }
};

test "add list done remove" {
    const gpa = std.testing.allocator;
    var list = TodoList.init(gpa);
    defer list.deinit();

    const a = try list.addNew("first", 10);
    try std.testing.expectEqual(@as(u64, 1), a.id);
    _ = try list.addNew("second", 11);
    try std.testing.expectEqual(@as(u64, 3), list.next_id);

    try list.markDone(1, 20);
    try std.testing.expect(list.findById(1).?.status == .done);

    const removed = try list.removeById(2);
    defer removed.deinit(gpa);
    try std.testing.expectEqualStrings("second", removed.text);
    try std.testing.expectEqual(@as(usize, 1), list.items.items.len);

    // IDs are not reused
    const third = try list.addNew("third", 30);
    try std.testing.expectEqual(@as(u64, 3), third.id);
}

test "heal next_id" {
    const gpa = std.testing.allocator;
    var list = TodoList.init(gpa);
    defer list.deinit();
    const orphan = try todo_mod.create(gpa, 9, "x", 0);
    try list.items.append(gpa, orphan);
    list.next_id = 1;
    list.healIds();
    try std.testing.expectEqual(@as(u64, 10), list.next_id);
}
