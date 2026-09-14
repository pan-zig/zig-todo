//! Schema migration hooks (no-op for schema v1).

pub const current_version: u32 = 1;

pub fn needsMigration(file_version: u32) bool {
    return file_version < current_version;
}
