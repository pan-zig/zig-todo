//! Parsed CLI intent (P4).

const filter = @import("../domain/filter.zig");
const todo_mod = @import("../domain/todo.zig");
const list_mod = @import("../domain/list.zig");

pub const StatusFilter = filter.StatusFilter;
pub const Priority = todo_mod.Priority;
pub const max_cli_tags = todo_mod.max_tags;
pub const DuePatch = list_mod.TodoList.DuePatch;

pub const TagBuf = struct {
    items: [max_cli_tags][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const TagBuf) []const []const u8 {
        return self.items[0..self.len];
    }

    pub fn append(self: *TagBuf, tag: []const u8) bool {
        if (self.len >= self.items.len) return false;
        self.items[self.len] = tag;
        self.len += 1;
        return true;
    }
};

pub const AddArgs = struct {
    text: []const u8,
    priority: Priority = .medium,
    tags: TagBuf = .{},
    due_at: ?i64 = null,
};

pub const ListArgs = struct {
    status: StatusFilter = .open,
    priority: ?Priority = null,
    tags: TagBuf = .{},
    overdue: bool = false,
};

pub const IdArgs = struct {
    id: u64,
};

pub const EditArgs = struct {
    id: u64,
    text: ?[]const u8 = null,
    priority: ?Priority = null,
    tags: ?TagBuf = null,
    due_at: ?DuePatch = null,
};

pub const ClearArgs = struct {
    done_only: bool,
};

pub const PathArgs = struct {
    path: []const u8,
};

pub const ExportArgs = struct {
    /// null => print to stdout
    path: ?[]const u8 = null,
};

pub const Command = union(enum) {
    help,
    version,
    add: AddArgs,
    list: ListArgs,
    show: IdArgs,
    done: IdArgs,
    undone: IdArgs,
    edit: EditArgs,
    rm: IdArgs,
    clear: ClearArgs,
    archive: ClearArgs,
    @"export": ExportArgs,
    import: PathArgs,
    unknown: []const u8,
    usage: []const u8,
};

pub const Parsed = struct {
    data_dir: ?[]const u8 = null,
    json: bool = false,
    quiet: bool = false,
    command: Command,
};
