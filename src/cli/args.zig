const commands = @import("commands.zig");

/// Parse argv (including program name at index 0) into a P0 command.
pub fn parse(argv: []const []const u8) commands.Command {
    if (argv.len <= 1) return .help;

    const first = argv[1];

    if (isHelpFlag(first) or eql(first, "help")) return .help;
    if (isVersionFlag(first) or eql(first, "version")) return .version;

    return .{ .unknown = first };
}

fn isHelpFlag(s: []const u8) bool {
    return eql(s, "-h") or eql(s, "--help");
}

fn isVersionFlag(s: []const u8) bool {
    return eql(s, "-V") or eql(s, "--version");
}

fn eql(a: []const u8, b: []const u8) bool {
    return a.len == b.len and for (a, b) |x, y| {
        if (x != y) break false;
    } else true;
}

test "parse defaults to help" {
    const cmd = parse(&.{"zig-todo"});
    try @import("std").testing.expect(cmd == .help);
}

test "parse version flags" {
    try @import("std").testing.expect(parse(&.{ "zig-todo", "version" }) == .version);
    try @import("std").testing.expect(parse(&.{ "zig-todo", "--version" }) == .version);
    try @import("std").testing.expect(parse(&.{ "zig-todo", "-V" }) == .version);
}

test "parse help flags" {
    try @import("std").testing.expect(parse(&.{ "zig-todo", "--help" }) == .help);
    try @import("std").testing.expect(parse(&.{ "zig-todo", "-h" }) == .help);
    try @import("std").testing.expect(parse(&.{ "zig-todo", "help" }) == .help);
}

test "parse unknown" {
    const cmd = parse(&.{ "zig-todo", "add" });
    try @import("std").testing.expect(cmd == .unknown);
}
