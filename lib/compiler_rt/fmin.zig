const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const arch = builtin.cpu.arch;
const common = @import("common.zig");

pub const panic = common.panic;

comptime {
    @export(&__fminh, .{ .name = "__fminh", .linkage = common.linkage, .visibility = common.visibility });
    @export(&fminf, .{ .name = "fminf", .linkage = common.linkage, .visibility = common.visibility });
    @export(&fmin, .{ .name = "fmin", .linkage = common.linkage, .visibility = common.visibility });
    @export(&__fminx, .{ .name = "__fminx", .linkage = common.linkage, .visibility = common.visibility });
    if (common.want_ppc_abi) {
        @export(&fminq, .{ .name = "fminf128", .linkage = common.linkage, .visibility = common.visibility });
    }
    @export(&fminq, .{ .name = "fminq", .linkage = common.linkage, .visibility = common.visibility });
    @export(&fminl, .{ .name = "fminl", .linkage = common.linkage, .visibility = common.visibility });
}

pub fn __fminh(x: f16, y: f16) callconv(.c) f16 {
    return generic_fmin(f16, x, y);
}

pub fn fminf(x: f32, y: f32) callconv(.c) f32 {
    return generic_fmin(f32, x, y);
}

pub fn fmin(x: f64, y: f64) callconv(.c) f64 {
    return generic_fmin(f64, x, y);
}

pub fn __fminx(x: f80, y: f80) callconv(.c) f80 {
    return generic_fmin(f80, x, y);
}

pub fn fminq(x: f128, y: f128) callconv(.c) f128 {
    return generic_fmin(f128, x, y);
}

pub fn fminl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        16 => return __fminh(x, y),
        32 => return fminf(x, y),
        64 => return fmin(x, y),
        80 => return __fminx(x, y),
        128 => return fminq(x, y),
        else => @compileError("unreachable"),
    }
}

inline fn generic_fmin(comptime T: type, x: T, y: T) T {
    if (math.isNan(x))
        return y;
    if (math.isNan(y))
        return x;
    if (math.signbit(x) != math.signbit(y))
        return if (math.signbit(x)) x else y;
    return if (x < y) x else y;
}

test "generic_fmin" {
    inline for ([_]type{ f32, f64, c_longdouble, f80, f128 }) |T| {
        const nan_val = math.nan(T);
        const Int = std.meta.Int(.unsigned, @bitSizeOf(T));

        try std.testing.expect(math.isNan(generic_fmin(T, nan_val, nan_val)));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, nan_val, 1.0));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, 1.0, nan_val));

        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, 1.0, 10.0));
        try std.testing.expectEqual(@as(T, -1.0), generic_fmin(T, 1.0, -1.0));

        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, -0.0))), @as(Int, @bitCast(generic_fmin(T, 0.0, -0.0))));
        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, -0.0))), @as(Int, @bitCast(generic_fmin(T, -0.0, 0.0))));
    }
}
