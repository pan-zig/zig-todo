//! Parsed CLI intent (P1).

const filter = @import("../domain/filter.zig");

pub const StatusFilter = filter.StatusFilter;

pub const AddArgs = struct {
    text: []const u8,
};

pub const ListArgs = struct {
    status: StatusFilter = .open,
};

pub const IdArgs = struct {
    id: u64,
};

pub const Command = union(enum) {
    help,
    version,
    add: AddArgs,
    list: ListArgs,
    done: IdArgs,
    rm: IdArgs,
    unknown: []const u8,
    usage: []const u8,
};

pub const Parsed = struct {
    data_dir: ?[]const u8 = null,
    command: Command,
};
