const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

pub const bak_suffix = ".bak";

pub const WriteError = error{IoError};

/// Atomically replace `file_name` inside `data_dir` with `bytes` (+ trailing newline).
/// If the target already exists, copy it to `file_name.bak` first.
pub fn writeAtomicReplace(
    io: Io,
    data_dir: []const u8,
    file_name: []const u8,
    bytes: []const u8,
) WriteError!void {
    var dir = openDataDir(io, data_dir) catch return error.IoError;
    defer dir.close(io);

    try backupIfExists(dir, io, file_name);

    var atomic = dir.createFileAtomic(io, file_name, .{
        .replace = true,
    }) catch return error.IoError;
    defer atomic.deinit(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = atomic.file.writer(io, &write_buf);
    file_writer.interface.writeAll(bytes) catch return error.IoError;
    file_writer.interface.writeAll("\n") catch return error.IoError;
    file_writer.interface.flush() catch return error.IoError;

    atomic.replace(io) catch return error.IoError;
}

fn openDataDir(io: Io, data_dir: []const u8) !Dir {
    if (std.fs.path.isAbsolute(data_dir)) {
        return Dir.openDirAbsolute(io, data_dir, .{});
    }
    return Dir.cwd().openDir(io, data_dir, .{});
}

fn backupIfExists(dir: Dir, io: Io, file_name: []const u8) WriteError!void {
    var bak_name_buf: [Io.Dir.max_name_bytes + bak_suffix.len]u8 = undefined;
    if (file_name.len + bak_suffix.len > bak_name_buf.len) return error.IoError;
    @memcpy(bak_name_buf[0..file_name.len], file_name);
    @memcpy(bak_name_buf[file_name.len..][0..bak_suffix.len], bak_suffix);
    const bak_name = bak_name_buf[0 .. file_name.len + bak_suffix.len];

    dir.copyFile(file_name, dir, bak_name, io, .{ .replace = true }) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return error.IoError,
    };
}

test "writeAtomicReplace creates bak on second write" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer gpa.free(data_dir);

    try writeAtomicReplace(io, data_dir, "todos.json", "{\"v\":1}");
    try writeAtomicReplace(io, data_dir, "todos.json", "{\"v\":2}");

    const main_path = try std.fs.path.join(gpa, &.{ data_dir, "todos.json" });
    defer gpa.free(main_path);
    const bak_path = try std.fs.path.join(gpa, &.{ data_dir, "todos.json.bak" });
    defer gpa.free(bak_path);

    const main_bytes = try Dir.readFileAlloc(.cwd(), io, main_path, gpa, .limited(1024));
    defer gpa.free(main_bytes);
    const bak_bytes = try Dir.readFileAlloc(.cwd(), io, bak_path, gpa, .limited(1024));
    defer gpa.free(bak_bytes);

    try std.testing.expect(std.mem.indexOf(u8, main_bytes, "\"v\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, bak_bytes, "\"v\":1") != null);
}
