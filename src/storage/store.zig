const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

const domain_list = @import("../domain/list.zig");
const domain_todo = @import("../domain/todo.zig");
const migrate = @import("migrate.zig");
const paths = @import("paths.zig");
const atomic_file = @import("atomic_file.zig");

pub const TodoList = domain_list.TodoList;
pub const Todo = domain_todo.Todo;
pub const Priority = domain_todo.Priority;
pub const Status = domain_todo.Status;

const schema_version = migrate.current_version;

/// On-disk JSON document (schema v1).
const Document = struct {
    version: u32,
    next_id: u64,
    todos: []TodoJson,
};

const TodoJson = struct {
    id: u64,
    text: []const u8,
    status: Status,
    priority: Priority = .medium,
    tags: []const []const u8 = &.{},
    created_at: i64,
    updated_at: i64,
    completed_at: ?i64 = null,
};

pub const StoreError = error{
    CorruptData,
    UnsupportedVersion,
    OutOfMemory,
    IoError,
};

pub const JsonFileStore = struct {
    allocator: Allocator,
    io: Io,
    data_dir: []const u8,
    file_path: []const u8,

    pub fn init(
        allocator: Allocator,
        io: Io,
        data_dir: []const u8,
    ) Allocator.Error!JsonFileStore {
        const owned_dir = try allocator.dupe(u8, data_dir);
        errdefer allocator.free(owned_dir);
        const file_path = try paths.todosFilePath(allocator, owned_dir);
        return .{
            .allocator = allocator,
            .io = io,
            .data_dir = owned_dir,
            .file_path = file_path,
        };
    }

    pub fn deinit(self: *JsonFileStore) void {
        self.allocator.free(self.data_dir);
        self.allocator.free(self.file_path);
    }

    pub fn load(self: *JsonFileStore) StoreError!TodoList {
        ensureDataDir(self) catch return error.IoError;

        const bytes = Dir.readFileAlloc(
            .cwd(),
            self.io,
            self.file_path,
            self.allocator,
            .limited(16 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => return TodoList.init(self.allocator),
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer self.allocator.free(bytes);

        if (std.mem.trim(u8, bytes, " \t\r\n").len == 0) {
            return TodoList.init(self.allocator);
        }

        var parsed = std.json.parseFromSlice(Document, self.allocator, bytes, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch return error.CorruptData;
        defer parsed.deinit();

        if (parsed.value.version > schema_version) return error.UnsupportedVersion;
        if (migrate.needsMigration(parsed.value.version)) {
            // Only v1 exists today; migrateInPlace will reject unknown steps.
            return error.UnsupportedVersion;
        }

        var list = TodoList.init(self.allocator);
        errdefer list.deinit();
        list.next_id = if (parsed.value.next_id == 0) 1 else parsed.value.next_id;

        for (parsed.value.todos) |item| {
            const text = try self.allocator.dupe(u8, item.text);
            errdefer self.allocator.free(text);

            var tags = try self.allocator.alloc([]const u8, item.tags.len);
            errdefer {
                for (tags) |t| self.allocator.free(t);
                self.allocator.free(tags);
            }
            for (item.tags, 0..) |tag, i| {
                tags[i] = try self.allocator.dupe(u8, tag);
            }

            try list.items.append(self.allocator, .{
                .id = item.id,
                .text = text,
                .status = item.status,
                .priority = item.priority,
                .tags = tags,
                .created_at = item.created_at,
                .updated_at = item.updated_at,
                .completed_at = item.completed_at,
            });
        }

        list.healIds();
        return list;
    }

    pub fn save(self: *JsonFileStore, list: *const TodoList) StoreError!void {
        ensureDataDir(self) catch return error.IoError;

        var todos_json = try self.allocator.alloc(TodoJson, list.items.items.len);
        defer self.allocator.free(todos_json);

        for (list.items.items, 0..) |item, i| {
            todos_json[i] = .{
                .id = item.id,
                .text = item.text,
                .status = item.status,
                .priority = item.priority,
                .tags = item.tags,
                .created_at = item.created_at,
                .updated_at = item.updated_at,
                .completed_at = item.completed_at,
            };
        }

        const doc = Document{
            .version = schema_version,
            .next_id = list.next_id,
            .todos = todos_json,
        };

        const bytes = std.json.Stringify.valueAlloc(self.allocator, doc, .{
            .whitespace = .indent_2,
        }) catch return error.OutOfMemory;
        defer self.allocator.free(bytes);

        atomic_file.writeAtomicReplace(self.io, self.data_dir, paths.file_name, bytes) catch return error.IoError;
    }

    fn ensureDataDir(self: *JsonFileStore) !void {
        try Dir.createDirPath(.cwd(), self.io, self.data_dir);
    }
};

test "json store roundtrip in temp dir" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer gpa.free(data_dir);

    var store = try JsonFileStore.init(gpa, io, data_dir);
    defer store.deinit();

    {
        var list = TodoList.init(gpa);
        defer list.deinit();
        _ = try list.addNew("first task", 100, .{ .priority = .high, .tags = &.{"docs"} });
        _ = try list.addNew("second", 101, .{});
        try list.markDone(1, 110);
        try store.save(&list);
    }

    {
        var loaded = try store.load();
        defer loaded.deinit();
        try std.testing.expectEqual(@as(usize, 2), loaded.items.items.len);
        try std.testing.expectEqualStrings("first task", loaded.items.items[0].text);
        try std.testing.expect(loaded.items.items[0].status == .done);
        try std.testing.expectEqualStrings("second", loaded.items.items[1].text);
        try std.testing.expectEqual(@as(u64, 3), loaded.next_id);
    }
}

test "json store rejects corrupt data" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer gpa.free(data_dir);

    try Dir.createDirPath(.cwd(), io, data_dir);
    const file_path = try paths.todosFilePath(gpa, data_dir);
    defer gpa.free(file_path);

    const file = try Dir.createFileAbsolute(io, file_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "{not-json");

    var store = try JsonFileStore.init(gpa, io, data_dir);
    defer store.deinit();
    try std.testing.expectError(error.CorruptData, store.load());
}

test "json store save creates bak snapshot" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer gpa.free(data_dir);

    var store = try JsonFileStore.init(gpa, io, data_dir);
    defer store.deinit();

    {
        var list = TodoList.init(gpa);
        defer list.deinit();
        _ = try list.addNew("one", 1, .{});
        try store.save(&list);
    }
    {
        var list = TodoList.init(gpa);
        defer list.deinit();
        _ = try list.addNew("two", 2, .{});
        try store.save(&list);
    }

    const bak_path = try std.fs.path.join(gpa, &.{ data_dir, paths.bak_file_name });
    defer gpa.free(bak_path);
    const bak_bytes = try Dir.readFileAlloc(.cwd(), io, bak_path, gpa, .limited(1024 * 1024));
    defer gpa.free(bak_bytes);
    try std.testing.expect(std.mem.indexOf(u8, bak_bytes, "one") != null);
}
