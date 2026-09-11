//! zig-todo library root — domain / storage / cli building blocks.

pub const version = @import("version.zig").version;

pub const cli = @import("cli.zig");
pub const domain = @import("domain.zig");
pub const storage = @import("storage.zig");
pub const util = @import("util.zig");
pub const app = @import("app.zig");

test {
    _ = cli;
    _ = domain;
    _ = storage;
    _ = util;
    _ = app;
}
