pub const ArchOsAbi = struct {
    arch: std.Target.Cpu.Arch,
    os: std.Target.Os.Tag,
    abi: std.Target.Abi,
    os_ver: ?std.SemanticVersion = null,

    // Minimum glibc version that provides support for the arch/os when ABI is GNU.
    glibc_min: ?std.SemanticVersion = null,
};

pub const available_libcs = [_]ArchOsAbi{
    .{
        .arch = .aarch64_be,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 3, .minor = 13, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 17, .patch = 0 },
    },
    .{
        .arch = .aarch64_be,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 3, .minor = 13, .patch = 0 },
    },
    .{
        .arch = .aarch64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 3, .minor = 7, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 17, .patch = 0 },
    },
    .{
        .arch = .aarch64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 3, .minor = 7, .patch = 0 },
    },
    .{
        .arch = .aarch64,
        .os = .windows,
        .abi = .gnu,
    },
    .{
        .arch = .aarch64,
        .os = .macos,
        .abi = .none,
        .os_ver = .{ .major = 11, .minor = 0, .patch = 0 },
    },
    .{
        .arch = .arc,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 4, .minor = 2, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 32, .patch = 0 },
    },
    .{
        .arch = .armeb,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .armeb,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .armeb,
        .os = .linux,
        .abi = .musleabi,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .armeb,
        .os = .linux,
        .abi = .musleabihf,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .arm,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .arm,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .arm,
        .os = .linux,
        .abi = .musleabi,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .arm,
        .os = .linux,
        .abi = .musleabihf,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .thumb,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .thumb,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .thumb,
        .os = .linux,
        .abi = .musleabi,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .thumb,
        .os = .linux,
        .abi = .musleabihf,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 80 },
    },
    .{
        .arch = .arm,
        .os = .windows,
        .abi = .gnu,
    },
    .{
        .arch = .csky,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 4, .minor = 20, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 29, .patch = 0 },
    },
    .{
        .arch = .csky,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 4, .minor = 20, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 29, .patch = 0 },
    },
    .{
        .arch = .x86,
        .os = .linux,
        .abi = .gnu,
    },
    .{
        .arch = .x86,
        .os = .linux,
        .abi = .musl,
    },
    .{
        .arch = .x86,
        .os = .windows,
        .abi = .gnu,
    },
    .{
        .arch = .loongarch64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 5, .minor = 19, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 36, .patch = 0 },
    },
    .{
        .arch = .loongarch64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 5, .minor = 19, .patch = 0 },
    },
    .{
        .arch = .m68k,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 1, .minor = 3, .patch = 94 },
    },
    .{
        .arch = .m68k,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 1, .minor = 3, .patch = 94 },
    },
    .{
        .arch = .mips64el,
        .os = .linux,
        .abi = .gnuabi64,
        .os_ver = .{ .major = 2, .minor = 3, .patch = 48 },
    },
    .{
        .arch = .mips64el,
        .os = .linux,
        .abi = .gnuabin32,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .mips64el,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 2, .minor = 3, .patch = 48 },
    },
    .{
        .arch = .mips64,
        .os = .linux,
        .abi = .gnuabi64,
        .os_ver = .{ .major = 2, .minor = 3, .patch = 48 },
    },
    .{
        .arch = .mips64,
        .os = .linux,
        .abi = .gnuabin32,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .mips64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 2, .minor = 3, .patch = 48 },
    },
    .{
        .arch = .mipsel,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .mipsel,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .mipsel,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .mips,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .mips,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .mips,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 82 },
    },
    .{
        .arch = .powerpc64le,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 3, .minor = 14, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 19, .patch = 0 },
    },
    .{
        .arch = .powerpc64le,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 3, .minor = 14, .patch = 0 },
    },
    .{
        .arch = .powerpc64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .powerpc64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 0 },
    },
    .{
        .arch = .powerpc,
        .os = .linux,
        .abi = .gnueabi,
        .os_ver = .{ .major = 1, .minor = 3, .patch = 45 },
    },
    .{
        .arch = .powerpc,
        .os = .linux,
        .abi = .gnueabihf,
        .os_ver = .{ .major = 1, .minor = 3, .patch = 45 },
    },
    .{
        .arch = .powerpc,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 1, .minor = 3, .patch = 45 },
    },
    .{
        .arch = .riscv32,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 4, .minor = 15, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 33, .patch = 0 },
    },
    .{
        .arch = .riscv32,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 4, .minor = 15, .patch = 0 },
    },
    .{
        .arch = .riscv64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 4, .minor = 15, .patch = 0 },
        .glibc_min = .{ .major = 2, .minor = 27, .patch = 0 },
    },
    .{
        .arch = .riscv64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 4, .minor = 15, .patch = 0 },
    },
    .{
        .arch = .s390x,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 2, .minor = 4, .patch = 2 },
    },
    .{
        .arch = .s390x,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 2, .minor = 4, .patch = 2 },
    },
    .{
        .arch = .sparc,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 1, .minor = 1, .patch = 71 },
    },
    .{
        .arch = .sparc64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 2, .minor = 1, .patch = 19 },
    },
    .{
        .arch = .wasm32,
        .os = .freestanding,
        .abi = .musl,
    },
    .{
        .arch = .wasm32,
        .os = .wasi,
        .abi = .musl,
    },
    .{
        .arch = .x86_64,
        .os = .linux,
        .abi = .gnu,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 4 },
    },
    .{
        .arch = .x86_64,
        .os = .linux,
        .abi = .gnux32,
        .os_ver = .{ .major = 3, .minor = 4, .patch = 0 },
    },
    .{
        .arch = .x86_64,
        .os = .linux,
        .abi = .musl,
        .os_ver = .{ .major = 2, .minor = 6, .patch = 4 },
    },
    .{
        .arch = .x86_64,
        .os = .windows,
        .abi = .gnu,
    },
    .{
        .arch = .x86_64,
        .os = .macos,
        .abi = .none,
        .os_ver = .{ .major = 10, .minor = 7, .patch = 0 },
    },
};

pub fn canBuildLibC(target: std.Target) bool {
    for (available_libcs) |libc| {
        if (target.cpu.arch == libc.arch and target.os.tag == libc.os and target.abi == libc.abi) {
            if (libc.os_ver) |libc_os_ver| {
                if (switch (target.os.getVersionRange()) {
                    .semver => |v| v,
                    .linux => |v| v.range,
                    else => null,
                }) |ver| {
                    if (ver.min.order(libc_os_ver) == .lt) return false;
                }
            }
            if (libc.glibc_min) |glibc_min| {
                if (target.os.version_range.linux.glibc.order(glibc_min) == .lt) return false;
            }
            return true;
        }
    }
    return false;
}

pub fn muslArchNameHeaders(arch: std.Target.Cpu.Arch) [:0]const u8 {
    return switch (arch) {
        .x86 => return "x86",
        else => muslArchName(arch),
    };
}

pub fn muslArchName(arch: std.Target.Cpu.Arch) [:0]const u8 {
    switch (arch) {
        .aarch64, .aarch64_be => return "aarch64",
        .arm, .armeb, .thumb, .thumbeb => return "arm",
        .x86 => return "i386",
        .loongarch64 => return "loongarch64",
        .m68k => return "m68k",
        .mips, .mipsel => return "mips",
        .mips64el, .mips64 => return "mips64",
        .powerpc => return "powerpc",
        .powerpc64, .powerpc64le => return "powerpc64",
        .riscv32 => return "riscv32",
        .riscv64 => return "riscv64",
        .s390x => return "s390x",
        .wasm32, .wasm64 => return "wasm",
        .x86_64 => return "x86_64",
        else => unreachable,
    }
}

const std = @import("std");
