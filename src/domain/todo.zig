const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Priority = enum { low, medium, high };
pub const Status = enum { open, done };

pub const max_text_len: usize = 1024;

pub const Todo = struct {
    id: u64,
    text: []const u8,
    status: Status,
    priority: Priority,
    tags: []const []const u8,
    created_at: i64,
    updated_at: i64,
    completed_at: ?i64,

    pub fn deinit(self: Todo, allocator: Allocator) void {
        allocator.free(self.text);
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
    }
};

pub const CreateError = error{
    EmptyText,
    TextTooLong,
    OutOfMemory,
};

/// Create a new open todo. Copies `text` into `allocator`-owned memory.
pub fn create(
    allocator: Allocator,
    id: u64,
    text: []const u8,
    now: i64,
) CreateError!Todo {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyText;
    if (trimmed.len > max_text_len) return error.TextTooLong;

    const owned_text = try allocator.dupe(u8, trimmed);
    errdefer allocator.free(owned_text);

    const tags = try allocator.alloc([]const u8, 0);
    errdefer allocator.free(tags);

    return .{
        .id = id,
        .text = owned_text,
        .status = .open,
        .priority = .medium,
        .tags = tags,
        .created_at = now,
        .updated_at = now,
        .completed_at = null,
    };
}

pub fn markDone(self: *Todo, now: i64) void {
    self.status = .done;
    self.completed_at = now;
    self.updated_at = now;
}

pub fn markOpen(self: *Todo, now: i64) void {
    self.status = .open;
    self.completed_at = null;
    self.updated_at = now;
}

test "create rejects empty text" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.EmptyText, create(gpa, 1, "   ", 0));
}

test "create trims and owns text" {
    const gpa = std.testing.allocator;
    const t = try create(gpa, 1, "  hello  ", 42);
    defer t.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 1), t.id);
    try std.testing.expectEqualStrings("hello", t.text);
    try std.testing.expect(t.status == .open);
    try std.testing.expect(t.completed_at == null);
    try std.testing.expectEqual(@as(i64, 42), t.created_at);
}

test "markDone sets completed_at" {
    const gpa = std.testing.allocator;
    var t = try create(gpa, 1, "x", 1);
    defer t.deinit(gpa);
    markDone(&t, 99);
    try std.testing.expect(t.status == .done);
    try std.testing.expectEqual(@as(i64, 99), t.completed_at.?);
}
