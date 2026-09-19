//! Schema migration framework.

const std = @import("std");

/// Current on-disk schema version (v2 adds optional `due_at`).
pub const current_version: u32 = 2;

pub fn needsMigration(file_version: u32) bool {
    return file_version < current_version;
}

pub fn isSupported(file_version: u32) bool {
    return file_version >= 1 and file_version <= current_version;
}

/// v1 → v2 is additive (`due_at` defaults to null); no structural rewrite required.
pub fn migrateOne(from: u32) error{UnsupportedVersion}!u32 {
    return switch (from) {
        1 => 2,
        else => error.UnsupportedVersion,
    };
}

test "needsMigration and support" {
    try std.testing.expect(needsMigration(1));
    try std.testing.expect(!needsMigration(2));
    try std.testing.expect(isSupported(1));
    try std.testing.expect(isSupported(2));
    try std.testing.expect(!isSupported(3));
    try std.testing.expectEqual(@as(u32, 2), try migrateOne(1));
}
