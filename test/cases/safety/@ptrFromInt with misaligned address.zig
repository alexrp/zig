const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "incorrect alignment")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var x: usize = 5;
    _ = &x;
    const y: [*]align(4) u8 = @ptrFromInt(x);
    _ = y;
    return error.TestFailed;
}
// run
// backend=stage2,llvm
// target=x86_64-linux,aarch64-linux
