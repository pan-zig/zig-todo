//! Schema migration framework.

const std = @import("std");

pub const current_version: u32 = 1;

pub fn needsMigration(file_version: u32) bool {
    return file_version < current_version;
}

/// Chain-migrate document root JSON value from `from_version` toward `current_version`.
/// Currently only schema v1 exists; this is a no-op placeholder for future versions.
pub fn migrateInPlace(file_version: u32, doc: *std.json.Value) !u32 {
    _ = doc;
    var version = file_version;
    while (version < current_version) {
        version = try migrateOne(version);
    }
    return version;
}

fn migrateOne(from: u32) !u32 {
    return switch (from) {
        // Example future: 1 => migrateV1toV2(doc), return 2
        else => error.UnsupportedVersion,
    };
}

test "needsMigration" {
    try std.testing.expect(!needsMigration(1));
    try std.testing.expect(needsMigration(0));
}
