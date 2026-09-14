const std = @import("std");
const commands = @import("commands.zig");

/// Parse argv (including program name at index 0).
pub fn parse(argv: []const []const u8) commands.Parsed {
    var data_dir: ?[]const u8 = null;

    var tokens: [64][]const u8 = undefined;
    var token_count: usize = 0;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (eql(arg, "--data-dir")) {
            if (i + 1 >= argv.len) {
                return .{ .command = .{ .usage = "--data-dir requires a path" } };
            }
            i += 1;
            data_dir = argv[i];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--data-dir=")) {
            const value = arg["--data-dir=".len..];
            if (value.len == 0) {
                return .{ .command = .{ .usage = "--data-dir requires a path" } };
            }
            data_dir = value;
            continue;
        }
        if (token_count >= tokens.len) {
            return .{ .command = .{ .usage = "too many arguments" } };
        }
        tokens[token_count] = arg;
        token_count += 1;
    }

    const rest = tokens[0..token_count];
    if (rest.len == 0) {
        return .{ .data_dir = data_dir, .command = .help };
    }

    const first = rest[0];
    if (isHelpFlag(first) or eql(first, "help")) {
        return .{ .data_dir = data_dir, .command = .help };
    }
    if (isVersionFlag(first) or eql(first, "version")) {
        return .{ .data_dir = data_dir, .command = .version };
    }

    if (eql(first, "add")) {
        if (rest.len != 2) {
            return .{ .data_dir = data_dir, .command = .{ .usage = "usage: zig-todo add \"<text>\"" } };
        }
        return .{
            .data_dir = data_dir,
            .command = .{ .add = .{ .text = rest[1] } },
        };
    }

    if (eql(first, "list") or eql(first, "ls")) {
        var status: commands.StatusFilter = .open;
        var j: usize = 1;
        while (j < rest.len) : (j += 1) {
            const a = rest[j];
            if (eql(a, "--status")) {
                if (j + 1 >= rest.len) {
                    return .{ .data_dir = data_dir, .command = .{ .usage = "--status requires open|done|all" } };
                }
                j += 1;
                status = parseStatus(rest[j]) orelse {
                    return .{ .data_dir = data_dir, .command = .{ .usage = "--status requires open|done|all" } };
                };
            } else if (std.mem.startsWith(u8, a, "--status=")) {
                status = parseStatus(a["--status=".len..]) orelse {
                    return .{ .data_dir = data_dir, .command = .{ .usage = "--status requires open|done|all" } };
                };
            } else {
                return .{ .data_dir = data_dir, .command = .{ .usage = "usage: zig-todo list [--status open|done|all]" } };
            }
        }
        return .{ .data_dir = data_dir, .command = .{ .list = .{ .status = status } } };
    }

    if (eql(first, "done")) {
        const id = parseId(rest) orelse {
            return .{ .data_dir = data_dir, .command = .{ .usage = "usage: zig-todo done <id>" } };
        };
        return .{ .data_dir = data_dir, .command = .{ .done = .{ .id = id } } };
    }

    if (eql(first, "rm") or eql(first, "delete")) {
        const id = parseId(rest) orelse {
            return .{ .data_dir = data_dir, .command = .{ .usage = "usage: zig-todo rm <id>" } };
        };
        return .{ .data_dir = data_dir, .command = .{ .rm = .{ .id = id } } };
    }

    return .{ .data_dir = data_dir, .command = .{ .unknown = first } };
}

fn parseId(rest: []const []const u8) ?u64 {
    if (rest.len != 2) return null;
    return std.fmt.parseInt(u64, rest[1], 10) catch null;
}

fn parseStatus(s: []const u8) ?commands.StatusFilter {
    if (eql(s, "open")) return .open;
    if (eql(s, "done")) return .done;
    if (eql(s, "all")) return .all;
    return null;
}

fn isHelpFlag(s: []const u8) bool {
    return eql(s, "-h") or eql(s, "--help");
}

fn isVersionFlag(s: []const u8) bool {
    return eql(s, "-V") or eql(s, "--version");
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "parse add list done rm" {
    const add_cmd = parse(&.{ "zig-todo", "add", "first task" });
    try std.testing.expect(add_cmd.command == .add);
    try std.testing.expectEqualStrings("first task", add_cmd.command.add.text);

    const list_cmd = parse(&.{ "zig-todo", "list", "--status", "all" });
    try std.testing.expect(list_cmd.command == .list);
    try std.testing.expect(list_cmd.command.list.status == .all);

    const done_cmd = parse(&.{ "zig-todo", "done", "3" });
    try std.testing.expect(done_cmd.command == .done);
    try std.testing.expectEqual(@as(u64, 3), done_cmd.command.done.id);

    const rm_cmd = parse(&.{ "zig-todo", "rm", "2" });
    try std.testing.expect(rm_cmd.command == .rm);

    const with_dir = parse(&.{ "zig-todo", "--data-dir", "/tmp/t", "list" });
    try std.testing.expectEqualStrings("/tmp/t", with_dir.data_dir.?);
    try std.testing.expect(with_dir.command == .list);
}

test "parse defaults to help" {
    try std.testing.expect(parse(&.{"zig-todo"}).command == .help);
}

test "parse version flags" {
    try std.testing.expect(parse(&.{ "zig-todo", "version" }).command == .version);
    try std.testing.expect(parse(&.{ "zig-todo", "--version" }).command == .version);
}
