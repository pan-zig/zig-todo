//! Argv → Parsed (P4).

const std = @import("std");
const commands = @import("commands.zig");
const date_util = @import("../util/date.zig");

pub const Parsed = commands.Parsed;
pub const Command = commands.Command;
pub const Priority = commands.Priority;
pub const StatusFilter = commands.StatusFilter;
pub const DuePatch = commands.DuePatch;

pub fn parse(argv: []const []const u8) Parsed {
    var data_dir: ?[]const u8 = null;
    var json = false;
    var quiet = false;
    var i: usize = 1;

    while (i < argv.len) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--")) {
            i += 1;
            break;
        }
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .help };
        }
        if (std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-V")) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .version };
        }
        if (std.mem.eql(u8, a, "--json")) {
            json = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--quiet") or std.mem.eql(u8, a, "-q")) {
            quiet = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--data-dir") or std.mem.eql(u8, a, "-d")) {
            if (i + 1 >= argv.len) {
                return .{ .command = .{ .usage = "缺少 --data-dir 参数值" } };
            }
            data_dir = argv[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, a, "-")) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
        }
        break;
    }

    if (i >= argv.len) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .list = .{} } };
    }

    const name = argv[i];
    i += 1;
    const rest = argv[i..];

    if (std.mem.eql(u8, name, "help") or std.mem.eql(u8, name, "--help") or std.mem.eql(u8, name, "-h")) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .help };
    }
    if (std.mem.eql(u8, name, "version") or std.mem.eql(u8, name, "--version") or std.mem.eql(u8, name, "-V")) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .version };
    }
    if (std.mem.eql(u8, name, "add")) {
        return parseAdd(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "list") or std.mem.eql(u8, name, "ls")) {
        return parseList(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "show")) {
        return parseIdCmd(data_dir, json, quiet, rest, .show);
    }
    if (std.mem.eql(u8, name, "done")) {
        return parseIdCmd(data_dir, json, quiet, rest, .done);
    }
    if (std.mem.eql(u8, name, "undone")) {
        return parseIdCmd(data_dir, json, quiet, rest, .undone);
    }
    if (std.mem.eql(u8, name, "rm") or std.mem.eql(u8, name, "remove") or std.mem.eql(u8, name, "delete")) {
        return parseIdCmd(data_dir, json, quiet, rest, .rm);
    }
    if (std.mem.eql(u8, name, "edit")) {
        return parseEdit(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "clear")) {
        return parseClear(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "archive")) {
        return parseArchive(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "export")) {
        return parseExport(data_dir, json, quiet, rest);
    }
    if (std.mem.eql(u8, name, "import")) {
        return parseImport(data_dir, json, quiet, rest);
    }

    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = name } };
}

const IdKind = enum { show, done, undone, rm };

fn parseIdCmd(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8, kind: IdKind) Parsed {
    if (rest.len != 1) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "需要一个 id" } };
    }
    const id = std.fmt.parseInt(u64, rest[0], 10) catch {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "id 必须是正整数" } };
    };
    if (id == 0) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "id 必须是正整数" } };
    }
    const args: commands.IdArgs = .{ .id = id };
    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = switch (kind) {
            .show => .{ .show = args },
            .done => .{ .done = args },
            .undone => .{ .undone = args },
            .rm => .{ .rm = args },
        },
    };
}

fn parseAdd(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    var priority: Priority = .medium;
    var tags: commands.TagBuf = .{};
    var due_at: ?i64 = null;
    var text_parts: [32][]const u8 = undefined;
    var text_n: usize = 0;
    var i: usize = 0;

    while (i < rest.len) {
        const a = rest[i];
        if (std.mem.eql(u8, a, "--priority") or std.mem.eql(u8, a, "-p")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --priority 值" } };
            }
            priority = parsePriority(rest[i + 1]) orelse {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "priority 应为 low|medium|high" } };
            };
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--tag") or std.mem.eql(u8, a, "-t")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --tag 值" } };
            }
            if (!tags.append(rest[i + 1])) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标签数量过多" } };
            }
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--due")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --due 值" } };
            }
            due_at = date_util.parseDueAt(rest[i + 1]) orelse {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "日期格式应为 YYYY-MM-DD" } };
            };
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, a, "-")) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
        }
        if (text_n >= text_parts.len) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标题过长" } };
        }
        text_parts[text_n] = a;
        text_n += 1;
        i += 1;
    }

    if (text_n == 0) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "add 需要标题" } };
    }

    const text = joinWords(text_parts[0..text_n]) catch {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标题过长" } };
    };

    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .add = .{ .text = text, .priority = priority, .tags = tags, .due_at = due_at } },
    };
}

fn parseList(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    var status: StatusFilter = .open;
    var priority: ?Priority = null;
    var tags: commands.TagBuf = .{};
    var overdue = false;
    var i: usize = 0;

    while (i < rest.len) {
        const a = rest[i];
        if (std.mem.eql(u8, a, "--all") or std.mem.eql(u8, a, "-a")) {
            status = .all;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--done")) {
            status = .done;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--open")) {
            status = .open;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--status") or std.mem.eql(u8, a, "-s")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --status 值" } };
            }
            const v = rest[i + 1];
            if (std.mem.eql(u8, v, "open")) status = .open
            else if (std.mem.eql(u8, v, "done")) status = .done
            else if (std.mem.eql(u8, v, "all")) status = .all
            else {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "status 应为 open|done|all" } };
            }
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--overdue")) {
            overdue = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--priority") or std.mem.eql(u8, a, "-p")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --priority 值" } };
            }
            priority = parsePriority(rest[i + 1]) orelse {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "priority 应为 low|medium|high" } };
            };
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--tag") or std.mem.eql(u8, a, "-t")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --tag 值" } };
            }
            if (!tags.append(rest[i + 1])) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标签数量过多" } };
            }
            i += 2;
            continue;
        }
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
    }

    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .list = .{ .status = status, .priority = priority, .tags = tags, .overdue = overdue } },
    };
}

fn parseEdit(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    if (rest.len < 1) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "edit 需要 id" } };
    }
    const id = std.fmt.parseInt(u64, rest[0], 10) catch {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "id 必须是正整数" } };
    };
    if (id == 0) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "id 必须是正整数" } };
    }

    var text: ?[]const u8 = null;
    var priority: ?Priority = null;
    var tags: ?commands.TagBuf = null;
    var due_at: ?DuePatch = null;
    var tag_buf: commands.TagBuf = .{};
    var tags_set = false;
    var text_parts: [32][]const u8 = undefined;
    var text_n: usize = 0;
    var i: usize = 1;

    while (i < rest.len) {
        const a = rest[i];
        if (std.mem.eql(u8, a, "--text") or std.mem.eql(u8, a, "-d")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --text/-d 值" } };
            }
            text = rest[i + 1];
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--priority") or std.mem.eql(u8, a, "-p")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --priority 值" } };
            }
            priority = parsePriority(rest[i + 1]) orelse {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "priority 应为 low|medium|high" } };
            };
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--tag") or std.mem.eql(u8, a, "-t")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --tag 值" } };
            }
            if (!tag_buf.append(rest[i + 1])) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标签数量过多" } };
            }
            tags_set = true;
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, a, "--due")) {
            if (i + 1 >= rest.len) {
                return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "缺少 --due 值" } };
            }
            if (std.mem.eql(u8, rest[i + 1], "none") or std.mem.eql(u8, rest[i + 1], "-")) {
                due_at = .{ .clear = {} };
            } else {
                const ts = date_util.parseDueAt(rest[i + 1]) orelse {
                    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "日期格式应为 YYYY-MM-DD 或 none" } };
                };
                due_at = .{ .set = ts };
            }
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, a, "-")) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
        }
        if (text_n >= text_parts.len) {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标题过长" } };
        }
        text_parts[text_n] = a;
        text_n += 1;
        i += 1;
    }

    if (text_n > 0) {
        text = joinWords(text_parts[0..text_n]) catch {
            return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "标题过长" } };
        };
    }
    if (tags_set) tags = tag_buf;

    if (text == null and priority == null and tags == null and due_at == null) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "edit 至少需要一项修改" } };
    }

    return .{
        .data_dir = data_dir,
        .json = json,
        .quiet = quiet,
        .command = .{ .edit = .{ .id = id, .text = text, .priority = priority, .tags = tags, .due_at = due_at } },
    };
}

fn parseClear(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    var done_only = false;
    for (rest) |a| {
        if (std.mem.eql(u8, a, "--done")) {
            done_only = true;
            continue;
        }
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
    }
    if (!done_only) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "clear 目前仅支持 --done" } };
    }
    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .clear = .{ .done_only = true } } };
}

fn parseArchive(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    var done_only = false;
    for (rest) |a| {
        if (std.mem.eql(u8, a, "--done")) {
            done_only = true;
            continue;
        }
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .unknown = a } };
    }
    if (!done_only) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "archive 目前仅支持 --done" } };
    }
    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .archive = .{ .done_only = true } } };
}

fn parseExport(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    if (rest.len == 0) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .@"export" = .{ .path = null } } };
    }
    if (rest.len == 1) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .@"export" = .{ .path = rest[0] } } };
    }
    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "export 最多接受一个路径" } };
}

fn parseImport(data_dir: ?[]const u8, json: bool, quiet: bool, rest: []const []const u8) Parsed {
    if (rest.len != 1) {
        return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .usage = "import 需要一个文件路径" } };
    }
    return .{ .data_dir = data_dir, .json = json, .quiet = quiet, .command = .{ .import = .{ .path = rest[0] } } };
}

fn parsePriority(s: []const u8) ?Priority {
    if (std.mem.eql(u8, s, "low") or std.mem.eql(u8, s, "l")) return .low;
    if (std.mem.eql(u8, s, "medium") or std.mem.eql(u8, s, "med") or std.mem.eql(u8, s, "m")) return .medium;
    if (std.mem.eql(u8, s, "high") or std.mem.eql(u8, s, "h")) return .high;
    return null;
}

var join_buf: [512]u8 = undefined;

fn joinWords(parts: []const []const u8) error{OutOfMemory}![]const u8 {
    if (parts.len == 1) return parts[0];
    var len: usize = 0;
    for (parts, 0..) |p, idx| {
        if (idx > 0) {
            if (len >= join_buf.len) return error.OutOfMemory;
            join_buf[len] = ' ';
            len += 1;
        }
        if (len + p.len > join_buf.len) return error.OutOfMemory;
        @memcpy(join_buf[len..][0..p.len], p);
        len += p.len;
    }
    return join_buf[0..len];
}

test "parse add with due" {
    const argv = [_][]const u8{ "todo", "add", "--due", "2026-12-31", "deadline" };
    const p = parse(&argv);
    try std.testing.expect(p.command == .add);
    try std.testing.expect(p.command.add.due_at != null);
}

test "parse list overdue" {
    const argv = [_][]const u8{ "todo", "list", "--overdue" };
    const p = parse(&argv);
    try std.testing.expect(p.command == .list);
    try std.testing.expect(p.command.list.overdue);
}

test "parse export import archive" {
    const a = parse(&[_][]const u8{ "todo", "export", "out.json" });
    try std.testing.expect(a.command == .@"export");
    try std.testing.expectEqualStrings("out.json", a.command.@"export".path.?);

    const b = parse(&[_][]const u8{ "todo", "import", "in.json" });
    try std.testing.expect(b.command == .import);

    const c = parse(&[_][]const u8{ "todo", "archive", "--done" });
    try std.testing.expect(c.command == .archive);
}
