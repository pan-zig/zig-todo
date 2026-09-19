const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

const domain_list = @import("../domain/list.zig");
const domain_todo = @import("../domain/todo.zig");
const migrate = @import("migrate.zig");
const paths = @import("paths.zig");
const atomic_file = @import("atomic_file.zig");
const file_lock = @import("file_lock.zig");

pub const TodoList = domain_list.TodoList;
pub const Todo = domain_todo.Todo;
pub const Priority = domain_todo.Priority;
pub const Status = domain_todo.Status;
pub const ImportItem = domain_list.ImportItem;

const schema_version = migrate.current_version;

const Document = struct {
    version: u32,
    next_id: u64,
    todos: []TodoJson,
};

const ArchiveDocument = struct {
    version: u32,
    todos: []TodoJson,
};

pub const TodoJson = struct {
    id: u64,
    text: []const u8,
    status: Status,
    priority: Priority = .medium,
    tags: []const []const u8 = &.{},
    created_at: i64,
    updated_at: i64,
    completed_at: ?i64 = null,
    due_at: ?i64 = null,
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
        var lock = file_lock.FileLock.acquire(self.allocator, self.io, self.data_dir) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer lock.release();
        return self.loadUnlocked();
    }

    pub fn save(self: *JsonFileStore, list: *const TodoList) StoreError!void {
        var lock = file_lock.FileLock.acquire(self.allocator, self.io, self.data_dir) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer lock.release();
        return self.saveUnlocked(list);
    }

    fn loadUnlocked(self: *JsonFileStore) StoreError!TodoList {
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

        if (!migrate.isSupported(parsed.value.version)) return error.UnsupportedVersion;

        var list = TodoList.init(self.allocator);
        errdefer list.deinit();
        list.next_id = if (parsed.value.next_id == 0) 1 else parsed.value.next_id;

        for (parsed.value.todos) |item| {
            try appendOwnedTodo(&list, self.allocator, item);
        }

        list.healIds();
        return list;
    }

    fn saveUnlocked(self: *JsonFileStore, list: *const TodoList) StoreError!void {
        ensureDataDir(self) catch return error.IoError;

        var todos_json = try self.allocator.alloc(TodoJson, list.items.items.len);
        defer self.allocator.free(todos_json);
        for (list.items.items, 0..) |item, i| {
            todos_json[i] = todoToJson(item);
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

    /// Export todos as a JSON array (machine-friendly).
    pub fn exportArrayBytes(self: *JsonFileStore, list: *const TodoList) StoreError![]u8 {
        var todos_json = try self.allocator.alloc(TodoJson, list.items.items.len);
        defer self.allocator.free(todos_json);
        for (list.items.items, 0..) |item, i| {
            todos_json[i] = todoToJson(item);
        }
        return std.json.Stringify.valueAlloc(self.allocator, todos_json, .{
            .whitespace = .indent_2,
        }) catch return error.OutOfMemory;
    }

    pub fn writeExportFile(self: *JsonFileStore, list: *const TodoList, abs_or_rel_path: []const u8) StoreError!void {
        const bytes = try self.exportArrayBytes(list);
        defer self.allocator.free(bytes);

        const file = Dir.createFileAbsolute(self.io, abs_or_rel_path, .{}) catch blk: {
            break :blk Dir.cwd().createFile(self.io, abs_or_rel_path, .{}) catch return error.IoError;
        };
        defer file.close(self.io);
        file.writeStreamingAll(self.io, bytes) catch return error.IoError;
        file.writeStreamingAll(self.io, "\n") catch return error.IoError;
    }

    pub fn importFromFile(self: *JsonFileStore, path: []const u8, now: i64) StoreError!usize {
        var lock = file_lock.FileLock.acquire(self.allocator, self.io, self.data_dir) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer lock.release();

        const bytes = Dir.readFileAlloc(.cwd(), self.io, path, self.allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer self.allocator.free(bytes);

        var list = try self.loadUnlocked();
        defer list.deinit();

        if (std.json.parseFromSlice([]TodoJson, self.allocator, bytes, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        })) |parsed| {
            defer parsed.deinit();
            const n = try importTodoJson(&list, parsed.value, now);
            try self.saveUnlocked(&list);
            return n;
        } else |_| {}

        var parsed = std.json.parseFromSlice(Document, self.allocator, bytes, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch return error.CorruptData;
        defer parsed.deinit();
        const n = try importTodoJson(&list, parsed.value.todos, now);
        try self.saveUnlocked(&list);
        return n;
    }

    pub fn archiveDone(self: *JsonFileStore) StoreError!usize {
        var lock = file_lock.FileLock.acquire(self.allocator, self.io, self.data_dir) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
        defer lock.release();

        var list = try self.loadUnlocked();
        defer list.deinit();

        const taken = list.takeDone() catch return error.OutOfMemory;
        defer {
            for (taken) |item| item.deinit(self.allocator);
            self.allocator.free(taken);
        }
        if (taken.len == 0) return 0;

        try appendArchive(self, taken);
        try self.saveUnlocked(&list);
        return taken.len;
    }

    fn appendArchive(self: *JsonFileStore, items: []const Todo) StoreError!void {
        ensureDataDir(self) catch return error.IoError;
        const archive_path = paths.archiveFilePath(self.allocator, self.data_dir) catch return error.OutOfMemory;
        defer self.allocator.free(archive_path);

        var existing: std.ArrayList(TodoJson) = .empty;
        defer existing.deinit(self.allocator);

        if (Dir.readFileAlloc(.cwd(), self.io, archive_path, self.allocator, .limited(32 * 1024 * 1024))) |bytes| {
            defer self.allocator.free(bytes);
            if (std.mem.trim(u8, bytes, " \t\r\n").len != 0) {
                var parsed = std.json.parseFromSlice(ArchiveDocument, self.allocator, bytes, .{
                    .allocate = .alloc_always,
                    .ignore_unknown_fields = true,
                }) catch return error.CorruptData;
                defer parsed.deinit();
                for (parsed.value.todos) |t| {
                    try existing.append(self.allocator, .{
                        .id = t.id,
                        .text = try self.allocator.dupe(u8, t.text),
                        .status = t.status,
                        .priority = t.priority,
                        .tags = try dupeTags(self.allocator, t.tags),
                        .created_at = t.created_at,
                        .updated_at = t.updated_at,
                        .completed_at = t.completed_at,
                        .due_at = t.due_at,
                    });
                }
            }
        } else |_| {}

        for (items) |item| {
            try existing.append(self.allocator, .{
                .id = item.id,
                .text = try self.allocator.dupe(u8, item.text),
                .status = item.status,
                .priority = item.priority,
                .tags = try dupeTags(self.allocator, item.tags),
                .created_at = item.created_at,
                .updated_at = item.updated_at,
                .completed_at = item.completed_at,
                .due_at = item.due_at,
            });
        }
        defer {
            for (existing.items) |t| {
                self.allocator.free(t.text);
                freeTags(self.allocator, t.tags);
            }
        }

        const doc = ArchiveDocument{
            .version = schema_version,
            .todos = existing.items,
        };
        const bytes = std.json.Stringify.valueAlloc(self.allocator, doc, .{
            .whitespace = .indent_2,
        }) catch return error.OutOfMemory;
        defer self.allocator.free(bytes);

        atomic_file.writeAtomicReplace(self.io, self.data_dir, paths.archive_file_name, bytes) catch return error.IoError;
    }

    fn ensureDataDir(self: *JsonFileStore) !void {
        try Dir.createDirPath(.cwd(), self.io, self.data_dir);
    }
};

fn todoToJson(item: Todo) TodoJson {
    return .{
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
}

fn appendOwnedTodo(list: *TodoList, allocator: Allocator, item: TodoJson) StoreError!void {
    const text = try allocator.dupe(u8, item.text);
    errdefer allocator.free(text);
    const tags = try dupeTags(allocator, item.tags);
    errdefer freeTags(allocator, tags);
    try list.items.append(allocator, .{
        .id = item.id,
        .text = text,
        .status = item.status,
        .priority = item.priority,
        .tags = tags,
        .created_at = item.created_at,
        .updated_at = item.updated_at,
        .completed_at = item.completed_at,
        .due_at = item.due_at,
    });
}

fn dupeTags(allocator: Allocator, tags: []const []const u8) StoreError![]const []const u8 {
    var out = try allocator.alloc([]const u8, tags.len);
    errdefer {
        for (out) |t| allocator.free(t);
        allocator.free(out);
    }
    for (tags, 0..) |tag, i| {
        out[i] = try allocator.dupe(u8, tag);
    }
    return out;
}

fn freeTags(allocator: Allocator, tags: []const []const u8) void {
    for (tags) |tag| allocator.free(tag);
    allocator.free(tags);
}

fn importTodoJson(list: *TodoList, todos: []TodoJson, now: i64) StoreError!usize {
    var count: usize = 0;
    for (todos) |t| {
        _ = list.addNew(t.text, now, .{
            .priority = t.priority,
            .tags = t.tags,
            .due_at = t.due_at,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.CorruptData,
        };
        if (t.status == .done) {
            const id = list.next_id - 1;
            list.markDone(id, t.completed_at orelse now) catch {};
        }
        count += 1;
    }
    return count;
}

test "json store roundtrip with due_at" {
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
        _ = try list.addNew("first task", 100, .{ .priority = .high, .tags = &.{"docs"}, .due_at = 200 });
        try store.save(&list);
    }

    {
        var loaded = try store.load();
        defer loaded.deinit();
        try std.testing.expectEqual(@as(?i64, 200), loaded.items.items[0].due_at);
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

test "archive done todos" {
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
        _ = try list.addNew("open", 1, .{});
        _ = try list.addNew("done-one", 2, .{});
        try list.markDone(2, 3);
        try store.save(&list);
    }

    const n = try store.archiveDone();
    try std.testing.expectEqual(@as(usize, 1), n);

    var loaded = try store.load();
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.items.items.len);
    try std.testing.expectEqualStrings("open", loaded.items.items[0].text);
}
