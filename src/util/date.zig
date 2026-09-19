const std = @import("std");

/// Parse due date: Unix seconds, or `YYYY-MM-DD` (00:00:00 UTC).
pub fn parseDueAt(s: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, s, " \t\r\n");
    if (trimmed.len == 0) return null;

    if (std.fmt.parseInt(i64, trimmed, 10)) |ts| {
        return ts;
    } else |_| {}

    if (trimmed.len != 10) return null;
    if (trimmed[4] != '-' or trimmed[7] != '-') return null;

    const year = std.fmt.parseInt(i32, trimmed[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, trimmed[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, trimmed[8..10], 10) catch return null;
    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    if (year < 1970) return null;

    return civilToUnix(year, month, day);
}

fn civilToUnix(year: i32, month: u8, day: u8) i64 {
    // Howard Hinnant civil_from_days inverse (days since 1970-01-01).
    const y: i32 = if (month <= 2) year - 1 else year;
    const era: i32 = @divFloor(y, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const m: u32 = if (month > 2) month - 3 else month + 9;
    const doy: u32 = (153 * m + 2) / 5 + day - 1;
    const doe: u32 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    const days: i64 = @as(i64, era) * 146097 + @as(i64, @intCast(doe)) - 719468;
    return days * 86400;
}

pub fn formatDueDate(ts: i64, buf: *[16]u8) []const u8 {
    const days: i32 = @intCast(@divFloor(ts, 86400));
    const z: i32 = days + 719468;
    const era: i32 = @divFloor(z, 146097);
    const doe: u32 = @intCast(z - era * 146097);
    const yoe: u32 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    var y: i32 = @as(i32, @intCast(yoe)) + era * 400;
    const doy: u32 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp: u32 = (5 * doy + 2) / 153;
    const d: u32 = doy - (153 * mp + 2) / 5 + 1;
    const m: u32 = if (mp < 10) mp + 3 else mp - 9;
    y += @intFromBool(m <= 2);
    const yu: u32 = @intCast(y);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ yu, m, d }) catch "????-??-??";
}

test "parse YYYY-MM-DD and unix" {
    const ts = parseDueAt("1970-01-02").?;
    try std.testing.expectEqual(@as(i64, 86400), ts);
    try std.testing.expectEqual(@as(i64, 100), parseDueAt("100").?);

    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-02", formatDueDate(86400, &buf));
    try std.testing.expectEqualStrings("2020-01-01", formatDueDate(parseDueAt("2020-01-01").?, &buf));
}
