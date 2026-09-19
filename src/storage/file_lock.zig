const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;

const paths = @import("paths.zig");

pub const LockError = error{ IoError, OutOfMemory };

/// Exclusive advisory lock on `<data_dir>/todos.lock`.
pub const FileLock = struct {
    io: Io,
    file: File,

    pub fn acquire(allocator: Allocator, io: Io, data_dir: []const u8) LockError!FileLock {
        Dir.createDirPath(.cwd(), io, data_dir) catch return error.IoError;

        const lock_path = try std.fs.path.join(allocator, &.{ data_dir, paths.lock_file_name });
        defer allocator.free(lock_path);

        const file = Dir.createFileAbsolute(io, lock_path, .{
            .read = true,
            .truncate = false,
            .lock = .exclusive,
        }) catch return error.IoError;

        return .{ .io = io, .file = file };
    }

    pub fn release(self: *FileLock) void {
        self.file.close(self.io);
        self.* = undefined;
    }
};
