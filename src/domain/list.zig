const std = @import("std");
const Allocator = std.mem.Allocator;

const todo_mod = @import("todo.zig");
const id_mod = @import("id.zig");
const filter_mod = @import("filter.zig");

pub const Todo = todo_mod.Todo;
pub const StatusFilter = filter_mod.StatusFilter;
pub const Filter = filter_mod.Filter;
pub const Priority = todo_mod.Priority;
pub const CreateOptions = todo_mod.CreateOptions;

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

    pub fn addNew(
        self: *TodoList,
        text: []const u8,
        now: i64,
        options: CreateOptions,
    ) todo_mod.CreateError!Todo {
        const id = self.next_id;
        const item = try todo_mod.create(self.allocator, id, text, now, options);
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

    pub fn markOpen(self: *TodoList, id: u64, now: i64) error{NotFound}!void {
        const item = self.findById(id) orelse return error.NotFound;
        todo_mod.markOpen(item, now);
    }

    pub fn removeById(self: *TodoList, id: u64) error{NotFound}!Todo {
        const idx = self.findIndex(id) orelse return error.NotFound;
        return self.items.orderedRemove(idx);
    }

    pub const EditPatch = struct {
        text: ?[]const u8 = null,
        priority: ?Priority = null,
        /// If non-null, replace tags entirely (may be empty slice).
        tags: ?[]const []const u8 = null,
        /// null = unchanged; otherwise set/clear due_at.
        due_at: ?DuePatch = null,
    };

    pub const DuePatch = union(enum) {
        clear,
        set: i64,
    };

    pub fn edit(self: *TodoList, id: u64, patch: EditPatch, now: i64) (todo_mod.EditError || error{NotFound})!void {
        const item = self.findById(id) orelse return error.NotFound;
        if (patch.text) |text| try todo_mod.setText(item, self.allocator, text, now);
        if (patch.priority) |p| todo_mod.setPriority(item, p, now);
        if (patch.tags) |tags| try todo_mod.setTags(item, self.allocator, tags, now);
        if (patch.due_at) |due| switch (due) {
            .clear => todo_mod.setDueAt(item, null, now),
            .set => |ts| todo_mod.setDueAt(item, ts, now),
        };
    }

    /// Remove done todos and return them (caller owns). Used by archive.
    pub fn takeDone(self: *TodoList) Allocator.Error![]Todo {
        var out: std.ArrayList(Todo) = .empty;
        errdefer {
            for (out.items) |item| item.deinit(self.allocator);
            out.deinit(self.allocator);
        }
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (self.items.items[i].status == .done) {
                try out.append(self.allocator, self.items.orderedRemove(i));
            } else {
                i += 1;
            }
        }
        return try out.toOwnedSlice(self.allocator);
    }

    /// Import todos, assigning fresh IDs. Copies text/tags.
    pub fn importItems(
        self: *TodoList,
        items: []const ImportItem,
        now: i64,
    ) todo_mod.CreateError!usize {
        var count: usize = 0;
        for (items) |it| {
            _ = try self.addNew(it.text, now, .{
                .priority = it.priority,
                .tags = it.tags,
                .due_at = it.due_at,
            });
            // Preserve done status if requested.
            if (it.status == .done) {
                const id = self.next_id - 1;
                try self.markDone(id, it.completed_at orelse now);
            }
            count += 1;
        }
        return count;
    }

    /// Remove all done todos. Returns count removed.
    pub fn clearDone(self: *TodoList) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (self.items.items[i].status == .done) {
                const item = self.items.orderedRemove(i);
                item.deinit(self.allocator);
                removed += 1;
            } else {
                i += 1;
            }
        }
        return removed;
    }

    pub fn filtered(
        self: *const TodoList,
        filter: Filter,
        out: *std.ArrayList(*const Todo),
    ) Allocator.Error!void {
        out.clearRetainingCapacity();
        for (self.items.items) |*item| {
            if (filter_mod.matches(item.*, filter)) {
                try out.append(self.allocator, item);
            }
        }
    }
};

pub const ImportItem = struct {
    text: []const u8,
    status: todo_mod.Status = .open,
    priority: Priority = .medium,
    tags: []const []const u8 = &.{},
    due_at: ?i64 = null,
    completed_at: ?i64 = null,
};

test "add list done remove edit clear" {
    const gpa = std.testing.allocator;
    var list = TodoList.init(gpa);
    defer list.deinit();

    const a = try list.addNew("first", 10, .{ .priority = .high, .tags = &.{"docs"} });
    try std.testing.expectEqual(@as(u64, 1), a.id);
    _ = try list.addNew("second", 11, .{});
    try list.markDone(1, 20);
    try list.edit(2, .{ .text = "second-edited", .priority = .low }, 21);
    try std.testing.expectEqualStrings("second-edited", list.findById(2).?.text);

    const removed = try list.removeById(2);
    defer removed.deinit(gpa);

    const n = list.clearDone();
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(usize, 0), list.items.items.len);
}

test "heal next_id" {
    const gpa = std.testing.allocator;
    var list = TodoList.init(gpa);
    defer list.deinit();
    const orphan = try todo_mod.create(gpa, 9, "x", 0, .{});
    try list.items.append(gpa, orphan);
    list.next_id = 1;
    list.healIds();
    try std.testing.expectEqual(@as(u64, 10), list.next_id);
}

test "markDone NotFound" {
    const gpa = std.testing.allocator;
    var list = TodoList.init(gpa);
    defer list.deinit();
    try std.testing.expectError(error.NotFound, list.markDone(99, 1));
    try std.testing.expectError(error.NotFound, list.removeById(99));
}
