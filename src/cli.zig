//! CLI layer: argv parsing, command routing, output, exit codes.

pub const args = @import("cli/args.zig");
pub const commands = @import("cli/commands.zig");
pub const output = @import("cli/output.zig");
pub const exit_codes = @import("cli/exit_codes.zig");
