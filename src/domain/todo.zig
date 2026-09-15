const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Priority = enum { low, medium, high };
pub const Status = enum { open, done };

pub const max_text_len: usize = 1024;
pub const max_tag_len: usize = 64;
pub const max_tags: usize = 16;

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
        freeTags(allocator, self.tags);
    }

    pub fn hasTag(self: Todo, tag: []const u8) bool {
        const needle = std.mem.trim(u8, tag, " \t\r\n");
        for (self.tags) |t| {
            if (eqlAsciiIgnoreCase(t, needle)) return true;
        }
        return false;
    }
};

pub const CreateError = error{
    EmptyText,
    TextTooLong,
    EmptyTag,
    TagTooLong,
    TooManyTags,
    OutOfMemory,
};

pub const CreateOptions = struct {
    priority: Priority = .medium,
    /// Raw tags; will be normalized (lowercased, trimmed, deduped).
    tags: []const []const u8 = &.{},
};

pub const EditError = CreateError;

/// Create a new open todo. Copies text/tags into `allocator`-owned memory.
pub fn create(
    allocator: Allocator,
    id: u64,
    text: []const u8,
    now: i64,
    options: CreateOptions,
) CreateError!Todo {
    const owned_text = try copyText(allocator, text);
    errdefer allocator.free(owned_text);

    const owned_tags = try normalizeTags(allocator, options.tags);
    errdefer freeTags(allocator, owned_tags);

    return .{
        .id = id,
        .text = owned_text,
        .status = .open,
        .priority = options.priority,
        .tags = owned_tags,
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

pub fn setText(self: *Todo, allocator: Allocator, text: []const u8, now: i64) EditError!void {
    const owned = try copyText(allocator, text);
    allocator.free(self.text);
    self.text = owned;
    self.updated_at = now;
}

pub fn setPriority(self: *Todo, priority: Priority, now: i64) void {
    self.priority = priority;
    self.updated_at = now;
}

pub fn setTags(self: *Todo, allocator: Allocator, tags: []const []const u8, now: i64) EditError!void {
    const owned = try normalizeTags(allocator, tags);
    freeTags(allocator, self.tags);
    self.tags = owned;
    self.updated_at = now;
}

fn eqlAsciiIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}

pub fn parsePriority(s: []const u8) ?Priority {
    if (std.mem.eql(u8, s, "low")) return .low;
    if (std.mem.eql(u8, s, "medium") or std.mem.eql(u8, s, "med")) return .medium;
    if (std.mem.eql(u8, s, "high")) return .high;
    return null;
}

pub fn priorityString(p: Priority) []const u8 {
    return switch (p) {
        .low => "low",
        .medium => "med",
        .high => "high",
    };
}

pub fn priorityJsonString(p: Priority) []const u8 {
    return switch (p) {
        .low => "low",
        .medium => "medium",
        .high => "high",
    };
}

fn copyText(allocator: Allocator, text: []const u8) CreateError![]u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyText;
    if (trimmed.len > max_text_len) return error.TextTooLong;
    return try allocator.dupe(u8, trimmed);
}

/// Normalize tags: trim, ASCII lower, reject empty, dedupe, cap count/length.
pub fn normalizeTags(allocator: Allocator, raw: []const []const u8) CreateError![]const []const u8 {
    if (raw.len > max_tags) return error.TooManyTags;

    var tmp: [max_tags][]u8 = undefined;
    var count: usize = 0;

    for (raw) |tag| {
        const trimmed = std.mem.trim(u8, tag, " \t\r\n");
        if (trimmed.len == 0) return error.EmptyTag;
        if (trimmed.len > max_tag_len) return error.TagTooLong;

        var owned = try allocator.alloc(u8, trimmed.len);
        errdefer allocator.free(owned);
        for (trimmed, 0..) |c, i| {
            owned[i] = std.ascii.toLower(c);
        }

        var dup = false;
        for (tmp[0..count]) |existing| {
            if (std.mem.eql(u8, existing, owned)) {
                dup = true;
                break;
            }
        }
        if (dup) {
            allocator.free(owned);
            continue;
        }
        if (count >= max_tags) {
            allocator.free(owned);
            return error.TooManyTags;
        }
        tmp[count] = owned;
        count += 1;
    }

    const result = try allocator.alloc([]const u8, count);
    for (tmp[0..count], 0..) |t, i| result[i] = t;
    return result;
}

pub fn freeTags(allocator: Allocator, tags: []const []const u8) void {
    for (tags) |tag| allocator.free(tag);
    allocator.free(tags);
}

test "create rejects empty text" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.EmptyText, create(gpa, 1, "   ", 0, .{}));
}

test "create with priority and tags" {
    const gpa = std.testing.allocator;
    const t = try create(gpa, 1, "  hello  ", 42, .{
        .priority = .high,
        .tags = &.{ "Docs", "docs", "CLI" },
    });
    defer t.deinit(gpa);
    try std.testing.expectEqualStrings("hello", t.text);
    try std.testing.expect(t.priority == .high);
    try std.testing.expectEqual(@as(usize, 2), t.tags.len);
    try std.testing.expectEqualStrings("docs", t.tags[0]);
    try std.testing.expectEqualStrings("cli", t.tags[1]);
}

test "setText and setTags" {
    const gpa = std.testing.allocator;
    var t = try create(gpa, 1, "old", 1, .{});
    defer t.deinit(gpa);
    try setText(&t, gpa, "new", 2);
    try setTags(&t, gpa, &.{"a"}, 3);
    try std.testing.expectEqualStrings("new", t.text);
    try std.testing.expectEqualStrings("a", t.tags[0]);
    try std.testing.expectEqual(@as(i64, 3), t.updated_at);
}

test "markDone sets completed_at" {
    const gpa = std.testing.allocator;
    var t = try create(gpa, 1, "x", 1, .{});
    defer t.deinit(gpa);
    markDone(&t, 99);
    try std.testing.expect(t.status == .done);
    try std.testing.expectEqual(@as(i64, 99), t.completed_at.?);
    markOpen(&t, 100);
    try std.testing.expect(t.status == .open);
    try std.testing.expect(t.completed_at == null);
}
