const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;

pub const file_name = "todos.json";
pub const bak_file_name = "todos.json.bak";
pub const archive_file_name = "archive.json";
pub const lock_file_name = "todos.lock";

/// Resolve data directory.
/// Priority: override → ZIG_TODO_DATA_DIR → XDG_DATA_HOME/zig-todo → platform default.
pub fn resolveDataDir(
    allocator: Allocator,
    environ: Environ,
    override: ?[]const u8,
) (Allocator.Error || error{Unexpected})![]u8 {
    if (override) |dir| {
        return try allocator.dupe(u8, dir);
    }

    if (try envGet(allocator, environ, "ZIG_TODO_DATA_DIR")) |dir| {
        return dir;
    }

    if (try envGet(allocator, environ, "XDG_DATA_HOME")) |xdg| {
        defer allocator.free(xdg);
        return try std.fs.path.join(allocator, &.{ xdg, "zig-todo" });
    }

    if (builtin.os.tag == .windows) {
        if (try envGet(allocator, environ, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return try std.fs.path.join(allocator, &.{ appdata, "zig-todo" });
        }
        if (try envGet(allocator, environ, "USERPROFILE")) |profile| {
            defer allocator.free(profile);
            return try std.fs.path.join(allocator, &.{ profile, "AppData", "Roaming", "zig-todo" });
        }
        return try allocator.dupe(u8, "zig-todo-data");
    }

    if (try envGet(allocator, environ, "HOME")) |home| {
        defer allocator.free(home);
        if (builtin.os.tag == .macos) {
            return try std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "zig-todo" });
        }
        return try std.fs.path.join(allocator, &.{ home, ".local", "share", "zig-todo" });
    }

    return try allocator.dupe(u8, ".zig-todo");
}

pub fn todosFilePath(allocator: Allocator, data_dir: []const u8) Allocator.Error![]u8 {
    return try std.fs.path.join(allocator, &.{ data_dir, file_name });
}

pub fn archiveFilePath(allocator: Allocator, data_dir: []const u8) Allocator.Error![]u8 {
    return try std.fs.path.join(allocator, &.{ data_dir, archive_file_name });
}

fn envGet(allocator: Allocator, environ: Environ, key: []const u8) (Allocator.Error || error{Unexpected})!?[]u8 {
    return Environ.getAlloc(environ, allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        error.OutOfMemory => error.OutOfMemory,
        else => error.Unexpected,
    };
}

test "todosFilePath joins" {
    const gpa = std.testing.allocator;
    const p = try todosFilePath(gpa, "/tmp/data");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("/tmp/data/todos.json", p);
}
