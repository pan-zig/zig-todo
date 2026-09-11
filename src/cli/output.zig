const std = @import("std");
const Io = std.Io;

const version = @import("../version.zig").version;

pub fn printHelp(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(
        \\zig-todo — lightweight local todo CLI
        \\
        \\Usage:
        \\  zig-todo <command> [flags] [args]
        \\
        \\Commands:
        \\  version     Print version and exit
        \\  help        Show this help
        \\
        \\Global flags:
        \\  -h, --help     Show this help
        \\  -V, --version  Print version
        \\
        \\Coming soon (P1+):
        \\  add, list, done, rm, ...
        \\
        \\See docs/ for product and architecture notes.
        \\
    );
}

pub fn printVersion(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("zig-todo {s}\n", .{version});
}

pub fn printUsageError(writer: *Io.Writer, message: []const u8) Io.Writer.Error!void {
    try writer.print("error: {s}\n", .{message});
    try writer.writeAll("Try 'zig-todo --help' for usage.\n");
}
