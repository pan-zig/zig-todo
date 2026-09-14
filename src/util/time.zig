const std = @import("std");
const Io = std.Io;

/// Current wall-clock time as Unix seconds.
pub fn nowUnixSeconds(io: Io) i64 {
    return Io.Clock.real.now(io).toSeconds();
}
