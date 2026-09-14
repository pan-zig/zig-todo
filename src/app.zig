const std = @import("std");
const Io = std.Io;

const domain_list = @import("domain/list.zig");
const store_mod = @import("storage/store.zig");
const time_util = @import("util/time.zig");

pub const TodoList = domain_list.TodoList;
pub const StatusFilter = domain_list.StatusFilter;
pub const JsonFileStore = store_mod.JsonFileStore;

pub fn add(store: *JsonFileStore, text: []const u8, now_ts: i64) !u64 {
    var list = try store.load();
    defer list.deinit();
    const item = try list.addNew(text, now_ts);
    const id = item.id;
    try store.save(&list);
    return id;
}

pub fn loadAll(store: *JsonFileStore) !TodoList {
    return try store.load();
}

pub fn markDone(store: *JsonFileStore, id: u64, now_ts: i64) !void {
    var list = try store.load();
    defer list.deinit();
    try list.markDone(id, now_ts);
    try store.save(&list);
}

pub fn remove(store: *JsonFileStore, id: u64) !void {
    var list = try store.load();
    defer list.deinit();
    const removed = try list.removeById(id);
    removed.deinit(list.allocator);
    try store.save(&list);
}

pub fn now(io: Io) i64 {
    return time_util.nowUnixSeconds(io);
}
