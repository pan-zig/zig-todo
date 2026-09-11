//! Parsed CLI intent for P0 (help / version only).

pub const Command = union(enum) {
    help,
    version,
    unknown: []const u8,
};
