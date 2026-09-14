const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;

pub const file_name = "todos.json";

/// Resolve data directory.
/// Priority: override → ZIG_TODO_DATA_DIR → XDG_DATA_HOME/zig-todo → platform default.
pub fn resolveDataDir(
    allocator: Allocator,
    environ: Environ,
    override: ?[]const u8,
) Allocator.Error![]u8 {
    if (override) |dir| {
        return try allocator.dupe(u8, dir);
    }

    if (Environ.getPosix(environ, "ZIG_TODO_DATA_DIR")) |dir| {
        return try allocator.dupe(u8, dir);
    }

    if (Environ.getPosix(environ, "XDG_DATA_HOME")) |xdg| {
        return try std.fs.path.join(allocator, &.{ xdg, "zig-todo" });
    }

    const home = Environ.getPosix(environ, "HOME") orelse {
        return try allocator.dupe(u8, ".zig-todo");
    };

    if (builtin.os.tag == .macos) {
        return try std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "zig-todo" });
    }

    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "zig-todo" });
}

pub fn todosFilePath(allocator: Allocator, data_dir: []const u8) Allocator.Error![]u8 {
    return try std.fs.path.join(allocator, &.{ data_dir, file_name });
}

test "todosFilePath joins" {
    const gpa = std.testing.allocator;
    const p = try todosFilePath(gpa, "/tmp/data");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("/tmp/data/todos.json", p);
}
