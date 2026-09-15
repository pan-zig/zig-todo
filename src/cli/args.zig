const std = @import("std");
const commands = @import("commands.zig");
const todo_mod = @import("../domain/todo.zig");

/// Parse argv (including program name at index 0).
pub fn parse(argv: []const []const u8) commands.Parsed {
    var data_dir: ?[]const u8 = null;
    var json = false;
    var quiet = false;

    var tokens: [96][]const u8 = undefined;
    var token_count: usize = 0;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (eql(arg, "--data-dir")) {
            if (i + 1 >= argv.len) return usage(null, json, quiet, "--data-dir requires a path");
            i += 1;
            data_dir = argv[i];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--data-dir=")) {
            const value = arg["--data-dir=".len..];
            if (value.len == 0) return usage(null, json, quiet, "--data-dir requires a path");
            data_dir = value;
            continue;
        }
        if (eql(arg, "--json")) {
            json = true;
            continue;
        }
        if (eql(arg, "-q") or eql(arg, "--quiet")) {
            quiet = true;
            continue;
        }
        if (token_count >= tokens.len) return usage(data_dir, json, quiet, "too many arguments");
        tokens[token_count] = arg;
        token_count += 1;
    }

    const rest = tokens[0..token_count];
    if (rest.len == 0) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .help };
    }

    const first = rest[0];
    if (isHelpFlag(first) or eql(first, "help")) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .help };
    }
    if (isVersionFlag(first) or eql(first, "version")) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .version };
    }

    if (eql(first, "add")) {
        return parseAdd(data_dir, json, quiet, rest[1..]);
    }
    if (eql(first, "list") or eql(first, "ls")) {
        return parseList(data_dir, json, quiet, rest[1..]);
    }
    if (eql(first, "show")) {
        const id = parseSingleId(rest) orelse {
            return usage(data_dir, json, quiet, "usage: zig-todo show <id>");
        };
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .show = .{ .id = id } } };
    }
    if (eql(first, "done")) {
        const id = parseSingleId(rest) orelse {
            return usage(data_dir, json, quiet, "usage: zig-todo done <id>");
        };
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .done = .{ .id = id } } };
    }
    if (eql(first, "undone")) {
        const id = parseSingleId(rest) orelse {
            return usage(data_dir, json, quiet, "usage: zig-todo undone <id>");
        };
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .undone = .{ .id = id } } };
    }
    if (eql(first, "edit")) {
        return parseEdit(data_dir, json, quiet, rest[1..]);
    }
    if (eql(first, "rm") or eql(first, "delete")) {
        const id = parseSingleId(rest) orelse {
            return usage(data_dir, json, quiet, "usage: zig-todo rm <id>");
        };
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .rm = .{ .id = id } } };
    }
    if (eql(first, "clear")) {
        return parseClear(data_dir, json, quiet, rest[1..]);
    }

    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = first } };
}

fn parseAdd(data_dir: ?[]const u8, json: bool, quiet: bool, args: []const []const u8) commands.Parsed {
    var priority: todo_mod.Priority = .medium;
    var tags: commands.TagBuf = .{};
    var text: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-p") or eql(a, "--priority")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "-p requires low|medium|high");
            i += 1;
            priority = todo_mod.parsePriority(args[i]) orelse {
                return usage(data_dir, json, quiet, "-p requires low|medium|high");
            };
        } else if (std.mem.startsWith(u8, a, "--priority=")) {
            priority = todo_mod.parsePriority(a["--priority=".len..]) orelse {
                return usage(data_dir, json, quiet, "-p requires low|medium|high");
            };
        } else if (eql(a, "-t") or eql(a, "--tag")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "-t requires a tag");
            i += 1;
            if (!tags.append(args[i])) return usage(data_dir, json, quiet, "too many tags");
        } else if (std.mem.startsWith(u8, a, "--tag=")) {
            const v = a["--tag=".len..];
            if (v.len == 0) return usage(data_dir, json, quiet, "-t requires a tag");
            if (!tags.append(v)) return usage(data_dir, json, quiet, "too many tags");
        } else if (std.mem.startsWith(u8, a, "-")) {
            return usage(data_dir, json, quiet, "usage: zig-todo add \"<text>\" [-p pri] [-t tag]...");
        } else {
            if (text != null) return usage(data_dir, json, quiet, "usage: zig-todo add \"<text>\" [-p pri] [-t tag]...");
            text = a;
        }
    }

    const t = text orelse {
        return usage(data_dir, json, quiet, "usage: zig-todo add \"<text>\" [-p pri] [-t tag]...");
    };
    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .add = .{ .text = t, .priority = priority, .tags = tags } },
    };
}

fn parseList(data_dir: ?[]const u8, json: bool, quiet: bool, args: []const []const u8) commands.Parsed {
    var status: commands.StatusFilter = .open;
    var priority: ?todo_mod.Priority = null;
    var tags: commands.TagBuf = .{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "--status")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "--status requires open|done|all");
            i += 1;
            status = parseStatus(args[i]) orelse {
                return usage(data_dir, json, quiet, "--status requires open|done|all");
            };
        } else if (std.mem.startsWith(u8, a, "--status=")) {
            status = parseStatus(a["--status=".len..]) orelse {
                return usage(data_dir, json, quiet, "--status requires open|done|all");
            };
        } else if (eql(a, "--priority") or eql(a, "-p")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "--priority requires low|medium|high");
            i += 1;
            priority = todo_mod.parsePriority(args[i]) orelse {
                return usage(data_dir, json, quiet, "--priority requires low|medium|high");
            };
        } else if (std.mem.startsWith(u8, a, "--priority=")) {
            priority = todo_mod.parsePriority(a["--priority=".len..]) orelse {
                return usage(data_dir, json, quiet, "--priority requires low|medium|high");
            };
        } else if (eql(a, "--tag") or eql(a, "-t")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "--tag requires a tag");
            i += 1;
            if (!tags.append(args[i])) return usage(data_dir, json, quiet, "too many tags");
        } else if (std.mem.startsWith(u8, a, "--tag=")) {
            const v = a["--tag=".len..];
            if (v.len == 0) return usage(data_dir, json, quiet, "--tag requires a tag");
            if (!tags.append(v)) return usage(data_dir, json, quiet, "too many tags");
        } else {
            return usage(data_dir, json, quiet, "usage: zig-todo list [--status ...] [--priority ...] [--tag ...]");
        }
    }

    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .list = .{ .status = status, .priority = priority, .tags = tags } },
    };
}

fn parseEdit(data_dir: ?[]const u8, json: bool, quiet: bool, args: []const []const u8) commands.Parsed {
    if (args.len == 0) return usage(data_dir, json, quiet, "usage: zig-todo edit <id> [-d text] [-p pri] [-t tag]...");

    const id = std.fmt.parseInt(u64, args[0], 10) catch {
        return usage(data_dir, json, quiet, "usage: zig-todo edit <id> [-d text] [-p pri] [-t tag]...");
    };

    var text: ?[]const u8 = null;
    var priority: ?todo_mod.Priority = null;
    var tags: ?commands.TagBuf = null;
    var tag_buf: commands.TagBuf = .{};
    var tags_set = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-d") or eql(a, "--text")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "-d requires text");
            i += 1;
            text = args[i];
        } else if (std.mem.startsWith(u8, a, "--text=")) {
            text = a["--text=".len..];
        } else if (eql(a, "-p") or eql(a, "--priority")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "-p requires low|medium|high");
            i += 1;
            priority = todo_mod.parsePriority(args[i]) orelse {
                return usage(data_dir, json, quiet, "-p requires low|medium|high");
            };
        } else if (std.mem.startsWith(u8, a, "--priority=")) {
            priority = todo_mod.parsePriority(a["--priority=".len..]) orelse {
                return usage(data_dir, json, quiet, "-p requires low|medium|high");
            };
        } else if (eql(a, "-t") or eql(a, "--tag")) {
            if (i + 1 >= args.len) return usage(data_dir, json, quiet, "-t requires a tag");
            i += 1;
            tags_set = true;
            if (!tag_buf.append(args[i])) return usage(data_dir, json, quiet, "too many tags");
        } else if (std.mem.startsWith(u8, a, "--tag=")) {
            const v = a["--tag=".len..];
            if (v.len == 0) return usage(data_dir, json, quiet, "-t requires a tag");
            tags_set = true;
            if (!tag_buf.append(v)) return usage(data_dir, json, quiet, "too many tags");
        } else {
            return usage(data_dir, json, quiet, "usage: zig-todo edit <id> [-d text] [-p pri] [-t tag]...");
        }
    }

    if (tags_set) tags = tag_buf;
    if (text == null and priority == null and tags == null) {
        return usage(data_dir, json, quiet, "edit requires at least one of -d/-p/-t");
    }

    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .edit = .{ .id = id, .text = text, .priority = priority, .tags = tags } },
    };
}

fn parseClear(data_dir: ?[]const u8, json: bool, quiet: bool, args: []const []const u8) commands.Parsed {
    var done_only = false;
    for (args) |a| {
        if (eql(a, "--done")) {
            done_only = true;
        } else {
            return usage(data_dir, json, quiet, "usage: zig-todo clear --done");
        }
    }
    if (!done_only) return usage(data_dir, json, quiet, "usage: zig-todo clear --done");
    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .clear = .{ .done_only = true } },
    };
}

fn usage(data_dir: ?[]const u8, json: bool, quiet: bool, msg: []const u8) commands.Parsed {
    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = msg } };
}

fn parseSingleId(rest: []const []const u8) ?u64 {
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

test "parse add with priority and tags" {
    const cmd = parse(&.{ "zig-todo", "add", "写文档", "-p", "high", "-t", "docs", "-t", "cli" });
    try std.testing.expect(cmd.command == .add);
    try std.testing.expectEqualStrings("写文档", cmd.command.add.text);
    try std.testing.expect(cmd.command.add.priority == .high);
    try std.testing.expectEqual(@as(usize, 2), cmd.command.add.tags.len);
}

test "parse list filters and json" {
    const cmd = parse(&.{ "zig-todo", "--json", "list", "--priority", "high", "--tag", "docs" });
    try std.testing.expect(cmd.json);
    try std.testing.expect(cmd.command == .list);
    try std.testing.expect(cmd.command.list.priority.? == .high);
    try std.testing.expectEqual(@as(usize, 1), cmd.command.list.tags.len);
}

test "parse edit and clear" {
    const edit_cmd = parse(&.{ "zig-todo", "edit", "1", "-d", "新描述" });
    try std.testing.expect(edit_cmd.command == .edit);
    try std.testing.expectEqualStrings("新描述", edit_cmd.command.edit.text.?);

    const clear_cmd = parse(&.{ "zig-todo", "clear", "--done" });
    try std.testing.expect(clear_cmd.command == .clear);
}
