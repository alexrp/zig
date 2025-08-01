const builtin = @import("builtin");
const std = @import("std.zig");
const math = std.math;
const mem = std.mem;
const io = std.io;
const posix = std.posix;
const fs = std.fs;
const testing = std.testing;
const root = @import("root");
const File = std.fs.File;
const windows = std.os.windows;
const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;
const native_endian = native_arch.endian();
const Writer = std.io.Writer;

pub const MemoryAccessor = @import("debug/MemoryAccessor.zig");
pub const FixedBufferReader = @import("debug/FixedBufferReader.zig");
pub const Dwarf = @import("debug/Dwarf.zig");
pub const Pdb = @import("debug/Pdb.zig");
pub const SelfInfo = @import("debug/SelfInfo.zig");
pub const Info = @import("debug/Info.zig");
pub const Coverage = @import("debug/Coverage.zig");

pub const simple_panic = @import("debug/simple_panic.zig");
pub const no_panic = @import("debug/no_panic.zig");

/// A fully-featured panic handler namespace which lowers all panics to calls to `panicFn`.
/// Safety panics will use formatted printing to provide a meaningful error message.
/// The signature of `panicFn` should match that of `defaultPanic`.
pub fn FullPanic(comptime panicFn: fn ([]const u8, ?usize) noreturn) type {
    return struct {
        pub const call = panicFn;
        pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "sentinel mismatch: expected {any}, found {any}", .{
                expected, found,
            });
        }
        pub fn unwrapError(err: anyerror) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "attempt to unwrap error: {s}", .{@errorName(err)});
        }
        pub fn outOfBounds(index: usize, len: usize) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "index out of bounds: index {d}, len {d}", .{ index, len });
        }
        pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "start index {d} is larger than end index {d}", .{ start, end });
        }
        pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "access of union field '{s}' while field '{s}' is active", .{
                @tagName(accessed), @tagName(active),
            });
        }
        pub fn sliceCastLenRemainder(src_len: usize) noreturn {
            @branchHint(.cold);
            std.debug.panicExtra(@returnAddress(), "slice length '{d}' does not divide exactly into destination elements", .{src_len});
        }
        pub fn reachedUnreachable() noreturn {
            @branchHint(.cold);
            call("reached unreachable code", @returnAddress());
        }
        pub fn unwrapNull() noreturn {
            @branchHint(.cold);
            call("attempt to use null value", @returnAddress());
        }
        pub fn castToNull() noreturn {
            @branchHint(.cold);
            call("cast causes pointer to be null", @returnAddress());
        }
        pub fn incorrectAlignment() noreturn {
            @branchHint(.cold);
            call("incorrect alignment", @returnAddress());
        }
        pub fn invalidErrorCode() noreturn {
            @branchHint(.cold);
            call("invalid error code", @returnAddress());
        }
        pub fn integerOutOfBounds() noreturn {
            @branchHint(.cold);
            call("integer does not fit in destination type", @returnAddress());
        }
        pub fn integerOverflow() noreturn {
            @branchHint(.cold);
            call("integer overflow", @returnAddress());
        }
        pub fn shlOverflow() noreturn {
            @branchHint(.cold);
            call("left shift overflowed bits", @returnAddress());
        }
        pub fn shrOverflow() noreturn {
            @branchHint(.cold);
            call("right shift overflowed bits", @returnAddress());
        }
        pub fn divideByZero() noreturn {
            @branchHint(.cold);
            call("division by zero", @returnAddress());
        }
        pub fn exactDivisionRemainder() noreturn {
            @branchHint(.cold);
            call("exact division produced remainder", @returnAddress());
        }
        pub fn integerPartOutOfBounds() noreturn {
            @branchHint(.cold);
            call("integer part of floating point value out of bounds", @returnAddress());
        }
        pub fn corruptSwitch() noreturn {
            @branchHint(.cold);
            call("switch on corrupt value", @returnAddress());
        }
        pub fn shiftRhsTooBig() noreturn {
            @branchHint(.cold);
            call("shift amount is greater than the type size", @returnAddress());
        }
        pub fn invalidEnumValue() noreturn {
            @branchHint(.cold);
            call("invalid enum value", @returnAddress());
        }
        pub fn forLenMismatch() noreturn {
            @branchHint(.cold);
            call("for loop over objects with non-equal lengths", @returnAddress());
        }
        pub fn copyLenMismatch() noreturn {
            @branchHint(.cold);
            call("source and destination arguments have non-equal lengths", @returnAddress());
        }
        pub fn memcpyAlias() noreturn {
            @branchHint(.cold);
            call("@memcpy arguments alias", @returnAddress());
        }
        pub fn noreturnReturned() noreturn {
            @branchHint(.cold);
            call("'noreturn' function returned", @returnAddress());
        }
    };
}

/// Unresolved source locations can be represented with a single `usize` that
/// corresponds to a virtual memory address of the program counter. Combined
/// with debug information, those values can be converted into a resolved
/// source location, including file, line, and column.
pub const SourceLocation = struct {
    line: u64,
    column: u64,
    file_name: []const u8,

    pub const invalid: SourceLocation = .{
        .line = 0,
        .column = 0,
        .file_name = &.{},
    };
};

pub const Symbol = struct {
    name: []const u8 = "???",
    compile_unit_name: []const u8 = "???",
    source_location: ?SourceLocation = null,
};

/// Deprecated because it returns the optimization mode of the standard
/// library, when the caller probably wants to use the optimization mode of
/// their own module.
pub const runtime_safety = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub const sys_can_stack_trace = switch (builtin.cpu.arch) {
    // Observed to go into an infinite loop.
    // TODO: Make this work.
    .mips,
    .mipsel,
    .mips64,
    .mips64el,
    .s390x,
    => false,

    // `@returnAddress()` in LLVM 10 gives
    // "Non-Emscripten WebAssembly hasn't implemented __builtin_return_address".
    // On Emscripten, Zig only supports `@returnAddress()` in debug builds
    // because Emscripten's implementation is very slow.
    .wasm32,
    .wasm64,
    => native_os == .emscripten and builtin.mode == .Debug,

    // `@returnAddress()` is unsupported in LLVM 13.
    .bpfel,
    .bpfeb,
    => false,

    else => true,
};

/// Allows the caller to freely write to stderr until `unlockStdErr` is called.
///
/// During the lock, any `std.Progress` information is cleared from the terminal.
pub fn lockStdErr() void {
    std.Progress.lockStdErr();
}

pub fn unlockStdErr() void {
    std.Progress.unlockStdErr();
}

/// Allows the caller to freely write to stderr until `unlockStdErr` is called.
///
/// During the lock, any `std.Progress` information is cleared from the terminal.
///
/// Returns a `Writer` with empty buffer, meaning that it is
/// in fact unbuffered and does not need to be flushed.
pub fn lockStderrWriter(buffer: []u8) *Writer {
    return std.Progress.lockStderrWriter(buffer);
}

pub fn unlockStderrWriter() void {
    std.Progress.unlockStderrWriter();
}

/// Print to stderr, silently returning on failure. Intended for use in "printf
/// debugging". Use `std.log` functions for proper logging.
///
/// Uses a 64-byte buffer for formatted printing which is flushed before this
/// function returns.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [64]u8 = undefined;
    const bw = lockStderrWriter(&buffer);
    defer unlockStderrWriter();
    nosuspend bw.print(fmt, args) catch return;
}

/// TODO multithreaded awareness
var self_debug_info: ?SelfInfo = null;

pub fn getSelfDebugInfo() !*SelfInfo {
    if (self_debug_info) |*info| {
        return info;
    } else {
        self_debug_info = try SelfInfo.open(getDebugInfoAllocator());
        return &self_debug_info.?;
    }
}

/// Tries to print a hexadecimal view of the bytes, unbuffered, and ignores any error returned.
/// Obtains the stderr mutex while dumping.
pub fn dumpHex(bytes: []const u8) void {
    const bw = lockStderrWriter(&.{});
    defer unlockStderrWriter();
    const ttyconf = std.io.tty.detectConfig(.stderr());
    dumpHexFallible(bw, ttyconf, bytes) catch {};
}

/// Prints a hexadecimal view of the bytes, returning any error that occurs.
pub fn dumpHexFallible(bw: *Writer, ttyconf: std.io.tty.Config, bytes: []const u8) !void {
    var chunks = mem.window(u8, bytes, 16, 16);
    while (chunks.next()) |window| {
        // 1. Print the address.
        const address = (@intFromPtr(bytes.ptr) + 0x10 * (std.math.divCeil(usize, chunks.index orelse bytes.len, 16) catch unreachable)) - 0x10;
        try ttyconf.setColor(bw, .dim);
        // We print the address in lowercase and the bytes in uppercase hexadecimal to distinguish them more.
        // Also, make sure all lines are aligned by padding the address.
        try bw.print("{x:0>[1]}  ", .{ address, @sizeOf(usize) * 2 });
        try ttyconf.setColor(bw, .reset);

        // 2. Print the bytes.
        for (window, 0..) |byte, index| {
            try bw.print("{X:0>2} ", .{byte});
            if (index == 7) try bw.writeByte(' ');
        }
        try bw.writeByte(' ');
        if (window.len < 16) {
            var missing_columns = (16 - window.len) * 3;
            if (window.len < 8) missing_columns += 1;
            try bw.splatByteAll(' ', missing_columns);
        }

        // 3. Print the characters.
        for (window) |byte| {
            if (std.ascii.isPrint(byte)) {
                try bw.writeByte(byte);
            } else {
                // Related: https://github.com/ziglang/zig/issues/7600
                if (ttyconf == .windows_api) {
                    try bw.writeByte('.');
                    continue;
                }

                // Let's print some common control codes as graphical Unicode symbols.
                // We don't want to do this for all control codes because most control codes apart from
                // the ones that Zig has escape sequences for are likely not very useful to print as symbols.
                switch (byte) {
                    '\n' => try bw.writeAll("␊"),
                    '\r' => try bw.writeAll("␍"),
                    '\t' => try bw.writeAll("␉"),
                    else => try bw.writeByte('.'),
                }
            }
        }
        try bw.writeByte('\n');
    }
}

test dumpHexFallible {
    const bytes: []const u8 = &.{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01, 0x12, 0x13 };
    var aw: std.io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    try dumpHexFallible(&aw.writer, .no_color, bytes);
    const expected = try std.fmt.allocPrint(std.testing.allocator,
        \\{x:0>[2]}  00 11 22 33 44 55 66 77  88 99 AA BB CC DD EE FF  .."3DUfw........
        \\{x:0>[2]}  01 12 13                                          ...
        \\
    , .{
        @intFromPtr(bytes.ptr),
        @intFromPtr(bytes.ptr) + 16,
        @sizeOf(usize) * 2,
    });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, aw.getWritten());
}

/// Tries to print the current stack trace to stderr, unbuffered, and ignores any error returned.
pub fn dumpCurrentStackTrace(start_addr: ?usize) void {
    const stderr = lockStderrWriter(&.{});
    defer unlockStderrWriter();
    nosuspend dumpCurrentStackTraceToWriter(start_addr, stderr) catch return;
}

/// Prints the current stack trace to the provided writer.
pub fn dumpCurrentStackTraceToWriter(start_addr: ?usize, writer: *Writer) !void {
    if (builtin.target.cpu.arch.isWasm()) {
        if (native_os == .wasi) {
            try writer.writeAll("Unable to dump stack trace: not implemented for Wasm\n");
        }
        return;
    }
    if (builtin.strip_debug_info) {
        try writer.writeAll("Unable to dump stack trace: debug info stripped\n");
        return;
    }
    const debug_info = getSelfDebugInfo() catch |err| {
        try writer.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)});
        return;
    };
    writeCurrentStackTrace(writer, debug_info, io.tty.detectConfig(.stderr()), start_addr) catch |err| {
        try writer.print("Unable to dump stack trace: {s}\n", .{@errorName(err)});
        return;
    };
}

pub const have_ucontext = posix.ucontext_t != void;

/// Platform-specific thread state. This contains register state, and on some platforms
/// information about the stack. This is not safe to trivially copy, because some platforms
/// use internal pointers within this structure. To make a copy, use `copyContext`.
pub const ThreadContext = blk: {
    if (native_os == .windows) {
        break :blk windows.CONTEXT;
    } else if (have_ucontext) {
        break :blk posix.ucontext_t;
    } else {
        break :blk void;
    }
};

/// Copies one context to another, updating any internal pointers
pub fn copyContext(source: *const ThreadContext, dest: *ThreadContext) void {
    if (!have_ucontext) return {};
    dest.* = source.*;
    relocateContext(dest);
}

/// Updates any internal pointers in the context to reflect its current location
pub fn relocateContext(context: *ThreadContext) void {
    return switch (native_os) {
        .macos => {
            context.mcontext = &context.__mcontext_data;
        },
        else => {},
    };
}

pub const have_getcontext = @TypeOf(posix.system.getcontext) != void;

/// Capture the current context. The register values in the context will reflect the
/// state after the platform `getcontext` function returns.
///
/// It is valid to call this if the platform doesn't have context capturing support,
/// in that case false will be returned.
pub inline fn getContext(context: *ThreadContext) bool {
    if (native_os == .windows) {
        context.* = std.mem.zeroes(windows.CONTEXT);
        windows.ntdll.RtlCaptureContext(context);
        return true;
    }

    const result = have_getcontext and posix.system.getcontext(context) == 0;
    if (native_os == .macos) {
        assert(context.mcsize == @sizeOf(std.c.mcontext_t));

        // On aarch64-macos, the system getcontext doesn't write anything into the pc
        // register slot, it only writes lr. This makes the context consistent with
        // other aarch64 getcontext implementations which write the current lr
        // (where getcontext will return to) into both the lr and pc slot of the context.
        if (native_arch == .aarch64) context.mcontext.ss.pc = context.mcontext.ss.lr;
    }

    return result;
}

/// Tries to print the stack trace starting from the supplied base pointer to stderr,
/// unbuffered, and ignores any error returned.
/// TODO multithreaded awareness
pub fn dumpStackTraceFromBase(context: *ThreadContext, stderr: *Writer) void {
    nosuspend {
        if (builtin.target.cpu.arch.isWasm()) {
            if (native_os == .wasi) {
                stderr.print("Unable to dump stack trace: not implemented for Wasm\n", .{}) catch return;
            }
            return;
        }
        if (builtin.strip_debug_info) {
            stderr.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
            return;
        }
        const debug_info = getSelfDebugInfo() catch |err| {
            stderr.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch return;
            return;
        };
        const tty_config = io.tty.detectConfig(.stderr());
        if (native_os == .windows) {
            // On x86_64 and aarch64, the stack will be unwound using RtlVirtualUnwind using the context
            // provided by the exception handler. On x86, RtlVirtualUnwind doesn't exist. Instead, a new backtrace
            // will be captured and frames prior to the exception will be filtered.
            // The caveat is that RtlCaptureStackBackTrace does not include the KiUserExceptionDispatcher frame,
            // which is where the IP in `context` points to, so it can't be used as start_addr.
            // Instead, start_addr is recovered from the stack.
            const start_addr = if (builtin.cpu.arch == .x86) @as(*const usize, @ptrFromInt(context.getRegs().bp + 4)).* else null;
            writeStackTraceWindows(stderr, debug_info, tty_config, context, start_addr) catch return;
            return;
        }

        var it = StackIterator.initWithContext(null, debug_info, context) catch return;
        defer it.deinit();

        // DWARF unwinding on aarch64-macos is not complete so we need to get pc address from mcontext
        const pc_addr = if (builtin.target.os.tag.isDarwin() and native_arch == .aarch64)
            context.mcontext.ss.pc
        else
            it.unwind_state.?.dwarf_context.pc;
        printSourceAtAddress(debug_info, stderr, pc_addr, tty_config) catch return;

        while (it.next()) |return_address| {
            printLastUnwindError(&it, debug_info, stderr, tty_config);

            // On arm64 macOS, the address of the last frame is 0x0 rather than 0x1 as on x86_64 macOS,
            // therefore, we do a check for `return_address == 0` before subtracting 1 from it to avoid
            // an overflow. We do not need to signal `StackIterator` as it will correctly detect this
            // condition on the subsequent iteration and return `null` thus terminating the loop.
            // same behaviour for x86-windows-msvc
            const address = if (return_address == 0) return_address else return_address - 1;
            printSourceAtAddress(debug_info, stderr, address, tty_config) catch return;
        } else printLastUnwindError(&it, debug_info, stderr, tty_config);
    }
}

/// Returns a slice with the same pointer as addresses, with a potentially smaller len.
/// On Windows, when first_address is not null, we ask for at least 32 stack frames,
/// and then try to find the first address. If addresses.len is more than 32, we
/// capture that many stack frames exactly, and then look for the first address,
/// chopping off the irrelevant frames and shifting so that the returned addresses pointer
/// equals the passed in addresses pointer.
pub fn captureStackTrace(first_address: ?usize, stack_trace: *std.builtin.StackTrace) void {
    if (native_os == .windows) {
        const addrs = stack_trace.instruction_addresses;
        const first_addr = first_address orelse {
            stack_trace.index = walkStackWindows(addrs[0..], null);
            return;
        };
        var addr_buf_stack: [32]usize = undefined;
        const addr_buf = if (addr_buf_stack.len > addrs.len) addr_buf_stack[0..] else addrs;
        const n = walkStackWindows(addr_buf[0..], null);
        const first_index = for (addr_buf[0..n], 0..) |addr, i| {
            if (addr == first_addr) {
                break i;
            }
        } else {
            stack_trace.index = 0;
            return;
        };
        const end_index = @min(first_index + addrs.len, n);
        const slice = addr_buf[first_index..end_index];
        // We use a for loop here because slice and addrs may alias.
        for (slice, 0..) |addr, i| {
            addrs[i] = addr;
        }
        stack_trace.index = slice.len;
    } else {
        // TODO: This should use the DWARF unwinder if .eh_frame_hdr is available (so that full debug info parsing isn't required).
        //       A new path for loading SelfInfo needs to be created which will only attempt to parse in-memory sections, because
        //       stopping to load other debug info (ie. source line info) from disk here is not required for unwinding.
        var it = StackIterator.init(first_address, null);
        defer it.deinit();
        for (stack_trace.instruction_addresses, 0..) |*addr, i| {
            addr.* = it.next() orelse {
                stack_trace.index = i;
                return;
            };
        }
        stack_trace.index = stack_trace.instruction_addresses.len;
    }
}

/// Tries to print a stack trace to stderr, unbuffered, and ignores any error returned.
/// TODO multithreaded awareness
pub fn dumpStackTrace(stack_trace: std.builtin.StackTrace) void {
    nosuspend {
        if (builtin.target.cpu.arch.isWasm()) {
            if (native_os == .wasi) {
                const stderr = lockStderrWriter(&.{});
                defer unlockStderrWriter();
                stderr.writeAll("Unable to dump stack trace: not implemented for Wasm\n") catch return;
            }
            return;
        }
        const stderr = lockStderrWriter(&.{});
        defer unlockStderrWriter();
        if (builtin.strip_debug_info) {
            stderr.writeAll("Unable to dump stack trace: debug info stripped\n") catch return;
            return;
        }
        const debug_info = getSelfDebugInfo() catch |err| {
            stderr.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch return;
            return;
        };
        writeStackTrace(stack_trace, stderr, debug_info, io.tty.detectConfig(.stderr())) catch |err| {
            stderr.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch return;
            return;
        };
    }
}

/// Invokes detectable illegal behavior when `ok` is `false`.
///
/// In Debug and ReleaseSafe modes, calls to this function are always
/// generated, and the `unreachable` statement triggers a panic.
///
/// In ReleaseFast and ReleaseSmall modes, calls to this function are optimized
/// away, and in fact the optimizer is able to use the assertion in its
/// heuristics.
///
/// Inside a test block, it is best to use the `std.testing` module rather than
/// this function, because this function may not detect a test failure in
/// ReleaseFast and ReleaseSmall mode. Outside of a test block, this assert
/// function is the correct function to use.
pub fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

/// Invokes detectable illegal behavior when the provided slice is not mapped
/// or lacks read permissions.
pub fn assertReadable(slice: []const volatile u8) void {
    if (!runtime_safety) return;
    for (slice) |*byte| _ = byte.*;
}

/// Invokes detectable illegal behavior when the provided array is not aligned
/// to the provided amount.
pub fn assertAligned(ptr: anytype, comptime alignment: std.mem.Alignment) void {
    const aligned_ptr: *align(alignment.toByteUnits()) anyopaque = @alignCast(@ptrCast(ptr));
    _ = aligned_ptr;
}

/// Equivalent to `@panic` but with a formatted message.
pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    @branchHint(.cold);
    panicExtra(@returnAddress(), format, args);
}

/// Equivalent to `@panic` but with a formatted message, and with an explicitly
/// provided return address.
pub fn panicExtra(
    ret_addr: ?usize,
    comptime format: []const u8,
    args: anytype,
) noreturn {
    @branchHint(.cold);

    const size = 0x1000;
    const trunc_msg = "(msg truncated)";
    var buf: [size + trunc_msg.len]u8 = undefined;
    var bw: Writer = .fixed(buf[0..size]);
    // a minor annoyance with this is that it will result in the NoSpaceLeft
    // error being part of the @panic stack trace (but that error should
    // only happen rarely)
    const msg = if (bw.print(format, args)) |_| bw.buffered() else |_| blk: {
        @memcpy(buf[size..], trunc_msg);
        break :blk &buf;
    };
    std.builtin.panic.call(msg, ret_addr);
}

/// Non-zero whenever the program triggered a panic.
/// The counter is incremented/decremented atomically.
var panicking = std.atomic.Value(u8).init(0);

/// Counts how many times the panic handler is invoked by this thread.
/// This is used to catch and handle panics triggered by the panic handler.
threadlocal var panic_stage: usize = 0;

/// Dumps a stack trace to standard error, then aborts.
pub fn defaultPanic(
    msg: []const u8,
    first_trace_addr: ?usize,
) noreturn {
    @branchHint(.cold);

    // For backends that cannot handle the language features depended on by the
    // default panic handler, we have a simpler panic handler:
    switch (builtin.zig_backend) {
        .stage2_aarch64,
        .stage2_arm,
        .stage2_powerpc,
        .stage2_riscv64,
        .stage2_spirv,
        .stage2_wasm,
        .stage2_x86,
        => @trap(),
        .stage2_x86_64 => switch (builtin.target.ofmt) {
            .elf, .macho => {},
            else => @trap(),
        },
        else => {},
    }

    switch (builtin.os.tag) {
        .freestanding, .other => {
            @trap();
        },
        .uefi => {
            const uefi = std.os.uefi;

            var utf16_buffer: [1000]u16 = undefined;
            const len_minus_3 = std.unicode.utf8ToUtf16Le(&utf16_buffer, msg) catch 0;
            utf16_buffer[len_minus_3..][0..3].* = .{ '\r', '\n', 0 };
            const len = len_minus_3 + 3;
            const exit_msg = utf16_buffer[0 .. len - 1 :0];

            // Output to both std_err and con_out, as std_err is easier
            // to read in stuff like QEMU at times, but, unlike con_out,
            // isn't visible on actual hardware if directly booted into
            inline for ([_]?*uefi.protocol.SimpleTextOutput{ uefi.system_table.std_err, uefi.system_table.con_out }) |o| {
                if (o) |out| {
                    out.setAttribute(.{ .foreground = .red }) catch {};
                    _ = out.outputString(exit_msg) catch {};
                    out.setAttribute(.{ .foreground = .white }) catch {};
                }
            }

            if (uefi.system_table.boot_services) |bs| {
                // ExitData buffer must be allocated using boot_services.allocatePool (spec: page 220)
                const exit_data = uefi.raw_pool_allocator.dupeZ(u16, exit_msg) catch @trap();
                bs.exit(uefi.handle, .aborted, exit_data) catch {};
            }
            @trap();
        },
        .cuda, .amdhsa => std.posix.abort(),
        .plan9 => {
            var status: [std.os.plan9.ERRMAX]u8 = undefined;
            const len = @min(msg.len, status.len - 1);
            @memcpy(status[0..len], msg[0..len]);
            status[len] = 0;
            std.os.plan9.exits(status[0..len :0]);
        },
        else => {},
    }

    if (enable_segfault_handler) {
        // If a segfault happens while panicking, we want it to actually segfault, not trigger
        // the handler.
        resetSegfaultHandler();
    }

    // Note there is similar logic in handleSegfaultPosix and handleSegfaultWindowsExtra.
    nosuspend switch (panic_stage) {
        0 => {
            panic_stage = 1;

            _ = panicking.fetchAdd(1, .seq_cst);

            {
                const stderr = lockStderrWriter(&.{});
                defer unlockStderrWriter();

                if (builtin.single_threaded) {
                    stderr.print("panic: ", .{}) catch posix.abort();
                } else {
                    const current_thread_id = std.Thread.getCurrentId();
                    stderr.print("thread {} panic: ", .{current_thread_id}) catch posix.abort();
                }
                stderr.print("{s}\n", .{msg}) catch posix.abort();

                if (@errorReturnTrace()) |t| dumpStackTrace(t.*);
                dumpCurrentStackTraceToWriter(first_trace_addr orelse @returnAddress(), stderr) catch {};
            }

            waitForOtherThreadToFinishPanicking();
        },
        1 => {
            panic_stage = 2;

            // A panic happened while trying to print a previous panic message.
            // We're still holding the mutex but that's fine as we're going to
            // call abort().
            fs.File.stderr().writeAll("aborting due to recursive panic\n") catch {};
        },
        else => {}, // Panicked while printing the recursive panic message.
    };

    posix.abort();
}

/// Must be called only after adding 1 to `panicking`. There are three callsites.
fn waitForOtherThreadToFinishPanicking() void {
    if (panicking.fetchSub(1, .seq_cst) != 1) {
        // Another thread is panicking, wait for the last one to finish
        // and call abort()
        if (builtin.single_threaded) unreachable;

        // Sleep forever without hammering the CPU
        var futex = std.atomic.Value(u32).init(0);
        while (true) std.Thread.Futex.wait(&futex, 0);
        unreachable;
    }
}

pub fn writeStackTrace(
    stack_trace: std.builtin.StackTrace,
    writer: *Writer,
    debug_info: *SelfInfo,
    tty_config: io.tty.Config,
) !void {
    if (builtin.strip_debug_info) return error.MissingDebugInfo;
    var frame_index: usize = 0;
    var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frame_index];
        try printSourceAtAddress(debug_info, writer, return_address - 1, tty_config);
    }

    if (stack_trace.index > stack_trace.instruction_addresses.len) {
        const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;

        tty_config.setColor(writer, .bold) catch {};
        try writer.print("({d} additional stack frames skipped...)\n", .{dropped_frames});
        tty_config.setColor(writer, .reset) catch {};
    }
}

pub const UnwindError = if (have_ucontext)
    @typeInfo(@typeInfo(@TypeOf(StackIterator.next_unwind)).@"fn".return_type.?).error_union.error_set
else
    void;

pub const StackIterator = struct {
    // Skip every frame before this address is found.
    first_address: ?usize,
    // Last known value of the frame pointer register.
    fp: usize,
    ma: MemoryAccessor = MemoryAccessor.init,

    // When SelfInfo and a register context is available, this iterator can unwind
    // stacks with frames that don't use a frame pointer (ie. -fomit-frame-pointer),
    // using DWARF and MachO unwind info.
    unwind_state: if (have_ucontext) ?struct {
        debug_info: *SelfInfo,
        dwarf_context: SelfInfo.UnwindContext,
        last_error: ?UnwindError = null,
        failed: bool = false,
    } else void = if (have_ucontext) null else {},

    pub fn init(first_address: ?usize, fp: ?usize) StackIterator {
        if (native_arch.isSPARC()) {
            // Flush all the register windows on stack.
            asm volatile (if (builtin.cpu.has(.sparc, .v9))
                    "flushw"
                else
                    "ta 3" // ST_FLUSH_WINDOWS
                ::: .{ .memory = true });
        }

        return StackIterator{
            .first_address = first_address,
            // TODO: this is a workaround for #16876
            //.fp = fp orelse @frameAddress(),
            .fp = fp orelse blk: {
                const fa = @frameAddress();
                break :blk fa;
            },
        };
    }

    pub fn initWithContext(first_address: ?usize, debug_info: *SelfInfo, context: *posix.ucontext_t) !StackIterator {
        // The implementation of DWARF unwinding on aarch64-macos is not complete. However, Apple mandates that
        // the frame pointer register is always used, so on this platform we can safely use the FP-based unwinder.
        if (builtin.target.os.tag.isDarwin() and native_arch == .aarch64)
            return init(first_address, @truncate(context.mcontext.ss.fp));

        if (SelfInfo.supports_unwinding) {
            var iterator = init(first_address, null);
            iterator.unwind_state = .{
                .debug_info = debug_info,
                .dwarf_context = try SelfInfo.UnwindContext.init(debug_info.allocator, context),
            };
            return iterator;
        }

        return init(first_address, null);
    }

    pub fn deinit(it: *StackIterator) void {
        it.ma.deinit();
        if (have_ucontext and it.unwind_state != null) it.unwind_state.?.dwarf_context.deinit();
    }

    pub fn getLastError(it: *StackIterator) ?struct {
        err: UnwindError,
        address: usize,
    } {
        if (!have_ucontext) return null;
        if (it.unwind_state) |*unwind_state| {
            if (unwind_state.last_error) |err| {
                unwind_state.last_error = null;
                return .{
                    .err = err,
                    .address = unwind_state.dwarf_context.pc,
                };
            }
        }

        return null;
    }

    // Offset of the saved BP wrt the frame pointer.
    const fp_offset = if (native_arch.isRISCV())
        // On RISC-V the frame pointer points to the top of the saved register
        // area, on pretty much every other architecture it points to the stack
        // slot where the previous frame pointer is saved.
        2 * @sizeOf(usize)
    else if (native_arch.isSPARC())
        // On SPARC the previous frame pointer is stored at 14 slots past %fp+BIAS.
        14 * @sizeOf(usize)
    else
        0;

    const fp_bias = if (native_arch.isSPARC())
        // On SPARC frame pointers are biased by a constant.
        2047
    else
        0;

    // Positive offset of the saved PC wrt the frame pointer.
    const pc_offset = if (native_arch == .powerpc64le)
        2 * @sizeOf(usize)
    else
        @sizeOf(usize);

    pub fn next(it: *StackIterator) ?usize {
        var address = it.next_internal() orelse return null;

        if (it.first_address) |first_address| {
            while (address != first_address) {
                address = it.next_internal() orelse return null;
            }
            it.first_address = null;
        }

        return address;
    }

    fn next_unwind(it: *StackIterator) !usize {
        const unwind_state = &it.unwind_state.?;
        const module = try unwind_state.debug_info.getModuleForAddress(unwind_state.dwarf_context.pc);
        switch (native_os) {
            .macos, .ios, .watchos, .tvos, .visionos => {
                // __unwind_info is a requirement for unwinding on Darwin. It may fall back to DWARF, but unwinding
                // via DWARF before attempting to use the compact unwind info will produce incorrect results.
                if (module.unwind_info) |unwind_info| {
                    if (SelfInfo.unwindFrameMachO(
                        unwind_state.debug_info.allocator,
                        module.base_address,
                        &unwind_state.dwarf_context,
                        &it.ma,
                        unwind_info,
                        module.eh_frame,
                    )) |return_address| {
                        return return_address;
                    } else |err| {
                        if (err != error.RequiresDWARFUnwind) return err;
                    }
                } else return error.MissingUnwindInfo;
            },
            else => {},
        }

        if (try module.getDwarfInfoForAddress(unwind_state.debug_info.allocator, unwind_state.dwarf_context.pc)) |di| {
            return SelfInfo.unwindFrameDwarf(
                unwind_state.debug_info.allocator,
                di,
                module.base_address,
                &unwind_state.dwarf_context,
                &it.ma,
                null,
            );
        } else return error.MissingDebugInfo;
    }

    fn next_internal(it: *StackIterator) ?usize {
        if (have_ucontext) {
            if (it.unwind_state) |*unwind_state| {
                if (!unwind_state.failed) {
                    if (unwind_state.dwarf_context.pc == 0) return null;
                    defer it.fp = unwind_state.dwarf_context.getFp() catch 0;
                    if (it.next_unwind()) |return_address| {
                        return return_address;
                    } else |err| {
                        unwind_state.last_error = err;
                        unwind_state.failed = true;

                        // Fall back to fp-based unwinding on the first failure.
                        // We can't attempt it again for other modules higher in the
                        // stack because the full register state won't have been unwound.
                    }
                }
            }
        }

        if (builtin.omit_frame_pointer) return null;

        const fp = if (comptime native_arch.isSPARC())
            // On SPARC the offset is positive. (!)
            math.add(usize, it.fp, fp_offset) catch return null
        else
            math.sub(usize, it.fp, fp_offset) catch return null;

        // Sanity check.
        if (fp == 0 or !mem.isAligned(fp, @alignOf(usize))) return null;
        const new_fp = math.add(usize, it.ma.load(usize, fp) orelse return null, fp_bias) catch
            return null;

        // Sanity check: the stack grows down thus all the parent frames must be
        // be at addresses that are greater (or equal) than the previous one.
        // A zero frame pointer often signals this is the last frame, that case
        // is gracefully handled by the next call to next_internal.
        if (new_fp != 0 and new_fp < it.fp) return null;
        const new_pc = it.ma.load(usize, math.add(usize, fp, pc_offset) catch return null) orelse
            return null;

        it.fp = new_fp;

        return new_pc;
    }
};

pub fn writeCurrentStackTrace(
    writer: *Writer,
    debug_info: *SelfInfo,
    tty_config: io.tty.Config,
    start_addr: ?usize,
) !void {
    if (native_os == .windows) {
        var context: ThreadContext = undefined;
        assert(getContext(&context));
        return writeStackTraceWindows(writer, debug_info, tty_config, &context, start_addr);
    }
    var context: ThreadContext = undefined;
    const has_context = getContext(&context);

    var it = (if (has_context) blk: {
        break :blk StackIterator.initWithContext(start_addr, debug_info, &context) catch null;
    } else null) orelse StackIterator.init(start_addr, null);
    defer it.deinit();

    while (it.next()) |return_address| {
        printLastUnwindError(&it, debug_info, writer, tty_config);

        // On arm64 macOS, the address of the last frame is 0x0 rather than 0x1 as on x86_64 macOS,
        // therefore, we do a check for `return_address == 0` before subtracting 1 from it to avoid
        // an overflow. We do not need to signal `StackIterator` as it will correctly detect this
        // condition on the subsequent iteration and return `null` thus terminating the loop.
        // same behaviour for x86-windows-msvc
        const address = return_address -| 1;
        try printSourceAtAddress(debug_info, writer, address, tty_config);
    } else printLastUnwindError(&it, debug_info, writer, tty_config);
}

pub noinline fn walkStackWindows(addresses: []usize, existing_context: ?*const windows.CONTEXT) usize {
    if (builtin.cpu.arch == .x86) {
        // RtlVirtualUnwind doesn't exist on x86
        return windows.ntdll.RtlCaptureStackBackTrace(0, addresses.len, @as(**anyopaque, @ptrCast(addresses.ptr)), null);
    }

    const tib = &windows.teb().NtTib;

    var context: windows.CONTEXT = undefined;
    if (existing_context) |context_ptr| {
        context = context_ptr.*;
    } else {
        context = std.mem.zeroes(windows.CONTEXT);
        windows.ntdll.RtlCaptureContext(&context);
    }

    var i: usize = 0;
    var image_base: windows.DWORD64 = undefined;
    var history_table: windows.UNWIND_HISTORY_TABLE = std.mem.zeroes(windows.UNWIND_HISTORY_TABLE);

    while (i < addresses.len) : (i += 1) {
        const current_regs = context.getRegs();
        if (windows.ntdll.RtlLookupFunctionEntry(current_regs.ip, &image_base, &history_table)) |runtime_function| {
            var handler_data: ?*anyopaque = null;
            var establisher_frame: u64 = undefined;
            _ = windows.ntdll.RtlVirtualUnwind(
                windows.UNW_FLAG_NHANDLER,
                image_base,
                current_regs.ip,
                runtime_function,
                &context,
                &handler_data,
                &establisher_frame,
                null,
            );
        } else {
            // leaf function
            context.setIp(@as(*usize, @ptrFromInt(current_regs.sp)).*);
            context.setSp(current_regs.sp + @sizeOf(usize));
        }

        const next_regs = context.getRegs();
        if (next_regs.sp < @intFromPtr(tib.StackLimit) or next_regs.sp > @intFromPtr(tib.StackBase)) {
            break;
        }

        if (next_regs.ip == 0) {
            break;
        }

        addresses[i] = next_regs.ip;
    }

    return i;
}

pub fn writeStackTraceWindows(
    writer: *Writer,
    debug_info: *SelfInfo,
    tty_config: io.tty.Config,
    context: *const windows.CONTEXT,
    start_addr: ?usize,
) !void {
    var addr_buf: [1024]usize = undefined;
    const n = walkStackWindows(addr_buf[0..], context);
    const addrs = addr_buf[0..n];
    const start_i: usize = if (start_addr) |saddr| blk: {
        for (addrs, 0..) |addr, i| {
            if (addr == saddr) break :blk i;
        }
        return;
    } else 0;
    for (addrs[start_i..]) |addr| {
        try printSourceAtAddress(debug_info, writer, addr - 1, tty_config);
    }
}

fn printUnknownSource(debug_info: *SelfInfo, writer: *Writer, address: usize, tty_config: io.tty.Config) !void {
    const module_name = debug_info.getModuleNameForAddress(address);
    return printLineInfo(
        writer,
        null,
        address,
        "???",
        module_name orelse "???",
        tty_config,
        printLineFromFileAnyOs,
    );
}

fn printLastUnwindError(it: *StackIterator, debug_info: *SelfInfo, writer: *Writer, tty_config: io.tty.Config) void {
    if (!have_ucontext) return;
    if (it.getLastError()) |unwind_error| {
        printUnwindError(debug_info, writer, unwind_error.address, unwind_error.err, tty_config) catch {};
    }
}

fn printUnwindError(debug_info: *SelfInfo, writer: *Writer, address: usize, err: UnwindError, tty_config: io.tty.Config) !void {
    const module_name = debug_info.getModuleNameForAddress(address) orelse "???";
    try tty_config.setColor(writer, .dim);
    if (err == error.MissingDebugInfo) {
        try writer.print("Unwind information for `{s}:0x{x}` was not available, trace may be incomplete\n\n", .{ module_name, address });
    } else {
        try writer.print("Unwind error at address `{s}:0x{x}` ({}), trace may be incomplete\n\n", .{ module_name, address, err });
    }
    try tty_config.setColor(writer, .reset);
}

pub fn printSourceAtAddress(debug_info: *SelfInfo, writer: *Writer, address: usize, tty_config: io.tty.Config) !void {
    const module = debug_info.getModuleForAddress(address) catch |err| switch (err) {
        error.MissingDebugInfo, error.InvalidDebugInfo => return printUnknownSource(debug_info, writer, address, tty_config),
        else => return err,
    };

    const symbol_info = module.getSymbolAtAddress(debug_info.allocator, address) catch |err| switch (err) {
        error.MissingDebugInfo, error.InvalidDebugInfo => return printUnknownSource(debug_info, writer, address, tty_config),
        else => return err,
    };
    defer if (symbol_info.source_location) |sl| debug_info.allocator.free(sl.file_name);

    return printLineInfo(
        writer,
        symbol_info.source_location,
        address,
        symbol_info.name,
        symbol_info.compile_unit_name,
        tty_config,
        printLineFromFileAnyOs,
    );
}

fn printLineInfo(
    writer: *Writer,
    source_location: ?SourceLocation,
    address: usize,
    symbol_name: []const u8,
    compile_unit_name: []const u8,
    tty_config: io.tty.Config,
    comptime printLineFromFile: anytype,
) !void {
    nosuspend {
        try tty_config.setColor(writer, .bold);

        if (source_location) |*sl| {
            try writer.print("{s}:{d}:{d}", .{ sl.file_name, sl.line, sl.column });
        } else {
            try writer.writeAll("???:?:?");
        }

        try tty_config.setColor(writer, .reset);
        try writer.writeAll(": ");
        try tty_config.setColor(writer, .dim);
        try writer.print("0x{x} in {s} ({s})", .{ address, symbol_name, compile_unit_name });
        try tty_config.setColor(writer, .reset);
        try writer.writeAll("\n");

        // Show the matching source code line if possible
        if (source_location) |sl| {
            if (printLineFromFile(writer, sl)) {
                if (sl.column > 0) {
                    // The caret already takes one char
                    const space_needed = @as(usize, @intCast(sl.column - 1));

                    try writer.splatByteAll(' ', space_needed);
                    try tty_config.setColor(writer, .green);
                    try writer.writeAll("^");
                    try tty_config.setColor(writer, .reset);
                }
                try writer.writeAll("\n");
            } else |err| switch (err) {
                error.EndOfFile, error.FileNotFound => {},
                error.BadPathName => {},
                error.AccessDenied => {},
                else => return err,
            }
        }
    }
}

fn printLineFromFileAnyOs(writer: *Writer, source_location: SourceLocation) !void {
    // Need this to always block even in async I/O mode, because this could potentially
    // be called from e.g. the event loop code crashing.
    var f = try fs.cwd().openFile(source_location.file_name, .{});
    defer f.close();
    // TODO fstat and make sure that the file has the correct size

    var buf: [4096]u8 = undefined;
    var amt_read = try f.read(buf[0..]);
    const line_start = seek: {
        var current_line_start: usize = 0;
        var next_line: usize = 1;
        while (next_line != source_location.line) {
            const slice = buf[current_line_start..amt_read];
            if (mem.indexOfScalar(u8, slice, '\n')) |pos| {
                next_line += 1;
                if (pos == slice.len - 1) {
                    amt_read = try f.read(buf[0..]);
                    current_line_start = 0;
                } else current_line_start += pos + 1;
            } else if (amt_read < buf.len) {
                return error.EndOfFile;
            } else {
                amt_read = try f.read(buf[0..]);
                current_line_start = 0;
            }
        }
        break :seek current_line_start;
    };
    const slice = buf[line_start..amt_read];
    if (mem.indexOfScalar(u8, slice, '\n')) |pos| {
        const line = slice[0 .. pos + 1];
        mem.replaceScalar(u8, line, '\t', ' ');
        return writer.writeAll(line);
    } else { // Line is the last inside the buffer, and requires another read to find delimiter. Alternatively the file ends.
        mem.replaceScalar(u8, slice, '\t', ' ');
        try writer.writeAll(slice);
        while (amt_read == buf.len) {
            amt_read = try f.read(buf[0..]);
            if (mem.indexOfScalar(u8, buf[0..amt_read], '\n')) |pos| {
                const line = buf[0 .. pos + 1];
                mem.replaceScalar(u8, line, '\t', ' ');
                return writer.writeAll(line);
            } else {
                const line = buf[0..amt_read];
                mem.replaceScalar(u8, line, '\t', ' ');
                try writer.writeAll(line);
            }
        }
        // Make sure printing last line of file inserts extra newline
        try writer.writeByte('\n');
    }
}

test printLineFromFileAnyOs {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const output_stream = &aw.writer;

    const allocator = std.testing.allocator;
    const join = std.fs.path.join;
    const expectError = std.testing.expectError;
    const expectEqualStrings = std.testing.expectEqualStrings;

    var test_dir = std.testing.tmpDir(.{});
    defer test_dir.cleanup();
    // Relies on testing.tmpDir internals which is not ideal, but SourceLocation requires paths.
    const test_dir_path = try join(allocator, &.{ ".zig-cache", "tmp", test_dir.sub_path[0..] });
    defer allocator.free(test_dir_path);

    // Cases
    {
        const path = try join(allocator, &.{ test_dir_path, "one_line.zig" });
        defer allocator.free(path);
        try test_dir.dir.writeFile(.{ .sub_path = "one_line.zig", .data = "no new lines in this file, but one is printed anyway" });

        try expectError(error.EndOfFile, printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 2, .column = 0 }));

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 1, .column = 0 });
        try expectEqualStrings("no new lines in this file, but one is printed anyway\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
    {
        const path = try fs.path.join(allocator, &.{ test_dir_path, "three_lines.zig" });
        defer allocator.free(path);
        try test_dir.dir.writeFile(.{
            .sub_path = "three_lines.zig",
            .data =
            \\1
            \\2
            \\3
            ,
        });

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 1, .column = 0 });
        try expectEqualStrings("1\n", aw.getWritten());
        aw.clearRetainingCapacity();

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 3, .column = 0 });
        try expectEqualStrings("3\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
    {
        const file = try test_dir.dir.createFile("line_overlaps_page_boundary.zig", .{});
        defer file.close();
        const path = try fs.path.join(allocator, &.{ test_dir_path, "line_overlaps_page_boundary.zig" });
        defer allocator.free(path);

        const overlap = 10;
        var buf: [16]u8 = undefined;
        var file_writer = file.writer(&buf);
        const writer = &file_writer.interface;
        try writer.splatByteAll('a', std.heap.page_size_min - overlap);
        try writer.writeByte('\n');
        try writer.splatByteAll('a', overlap);
        try writer.flush();

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 2, .column = 0 });
        try expectEqualStrings(("a" ** overlap) ++ "\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
    {
        const file = try test_dir.dir.createFile("file_ends_on_page_boundary.zig", .{});
        defer file.close();
        const path = try fs.path.join(allocator, &.{ test_dir_path, "file_ends_on_page_boundary.zig" });
        defer allocator.free(path);

        var file_writer = file.writer(&.{});
        const writer = &file_writer.interface;
        try writer.splatByteAll('a', std.heap.page_size_max);

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 1, .column = 0 });
        try expectEqualStrings(("a" ** std.heap.page_size_max) ++ "\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
    {
        const file = try test_dir.dir.createFile("very_long_first_line_spanning_multiple_pages.zig", .{});
        defer file.close();
        const path = try fs.path.join(allocator, &.{ test_dir_path, "very_long_first_line_spanning_multiple_pages.zig" });
        defer allocator.free(path);

        var file_writer = file.writer(&.{});
        const writer = &file_writer.interface;
        try writer.splatByteAll('a', 3 * std.heap.page_size_max);

        try expectError(error.EndOfFile, printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 2, .column = 0 }));

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 1, .column = 0 });
        try expectEqualStrings(("a" ** (3 * std.heap.page_size_max)) ++ "\n", aw.getWritten());
        aw.clearRetainingCapacity();

        try writer.writeAll("a\na");

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 1, .column = 0 });
        try expectEqualStrings(("a" ** (3 * std.heap.page_size_max)) ++ "a\n", aw.getWritten());
        aw.clearRetainingCapacity();

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = 2, .column = 0 });
        try expectEqualStrings("a\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
    {
        const file = try test_dir.dir.createFile("file_of_newlines.zig", .{});
        defer file.close();
        const path = try fs.path.join(allocator, &.{ test_dir_path, "file_of_newlines.zig" });
        defer allocator.free(path);

        var file_writer = file.writer(&.{});
        const writer = &file_writer.interface;
        const real_file_start = 3 * std.heap.page_size_min;
        try writer.splatByteAll('\n', real_file_start);
        try writer.writeAll("abc\ndef");

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = real_file_start + 1, .column = 0 });
        try expectEqualStrings("abc\n", aw.getWritten());
        aw.clearRetainingCapacity();

        try printLineFromFileAnyOs(output_stream, .{ .file_name = path, .line = real_file_start + 2, .column = 0 });
        try expectEqualStrings("def\n", aw.getWritten());
        aw.clearRetainingCapacity();
    }
}

/// TODO multithreaded awareness
var debug_info_allocator: ?mem.Allocator = null;
var debug_info_arena_allocator: std.heap.ArenaAllocator = undefined;
fn getDebugInfoAllocator() mem.Allocator {
    if (debug_info_allocator) |a| return a;

    debug_info_arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = debug_info_arena_allocator.allocator();
    debug_info_allocator = allocator;
    return allocator;
}

/// Whether or not the current target can print useful debug information when a segfault occurs.
pub const have_segfault_handling_support = switch (native_os) {
    .linux,
    .macos,
    .netbsd,
    .solaris,
    .illumos,
    .windows,
    => true,

    .freebsd, .openbsd => have_ucontext,
    else => false,
};

const enable_segfault_handler = std.options.enable_segfault_handler;
pub const default_enable_segfault_handler = runtime_safety and have_segfault_handling_support;

pub fn maybeEnableSegfaultHandler() void {
    if (enable_segfault_handler) {
        attachSegfaultHandler();
    }
}

var windows_segfault_handle: ?windows.HANDLE = null;

pub fn updateSegfaultHandler(act: ?*const posix.Sigaction) void {
    posix.sigaction(posix.SIG.SEGV, act, null);
    posix.sigaction(posix.SIG.ILL, act, null);
    posix.sigaction(posix.SIG.BUS, act, null);
    posix.sigaction(posix.SIG.FPE, act, null);
}

/// Attaches a global SIGSEGV handler which calls `@panic("segmentation fault");`
pub fn attachSegfaultHandler() void {
    if (!have_segfault_handling_support) {
        @compileError("segfault handler not supported for this target");
    }
    if (native_os == .windows) {
        windows_segfault_handle = windows.kernel32.AddVectoredExceptionHandler(0, handleSegfaultWindows);
        return;
    }
    const act = posix.Sigaction{
        .handler = .{ .sigaction = handleSegfaultPosix },
        .mask = posix.sigemptyset(),
        .flags = (posix.SA.SIGINFO | posix.SA.RESTART | posix.SA.RESETHAND),
    };
    updateSegfaultHandler(&act);
}

fn resetSegfaultHandler() void {
    if (native_os == .windows) {
        if (windows_segfault_handle) |handle| {
            assert(windows.kernel32.RemoveVectoredExceptionHandler(handle) != 0);
            windows_segfault_handle = null;
        }
        return;
    }
    const act = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    updateSegfaultHandler(&act);
}

fn handleSegfaultPosix(sig: i32, info: *const posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.c) noreturn {
    // Reset to the default handler so that if a segfault happens in this handler it will crash
    // the process. Also when this handler returns, the original instruction will be repeated
    // and the resulting segfault will crash the process rather than continually dump stack traces.
    resetSegfaultHandler();

    const addr = switch (native_os) {
        .linux => @intFromPtr(info.fields.sigfault.addr),
        .freebsd, .macos => @intFromPtr(info.addr),
        .netbsd => @intFromPtr(info.info.reason.fault.addr),
        .openbsd => @intFromPtr(info.data.fault.addr),
        .solaris, .illumos => @intFromPtr(info.reason.fault.addr),
        else => unreachable,
    };

    const code = if (native_os == .netbsd) info.info.code else info.code;
    nosuspend switch (panic_stage) {
        0 => {
            panic_stage = 1;
            _ = panicking.fetchAdd(1, .seq_cst);

            {
                lockStdErr();
                defer unlockStdErr();

                dumpSegfaultInfoPosix(sig, code, addr, ctx_ptr);
            }

            waitForOtherThreadToFinishPanicking();
        },
        else => {
            // panic mutex already locked
            dumpSegfaultInfoPosix(sig, code, addr, ctx_ptr);
        },
    };

    // We cannot allow the signal handler to return because when it runs the original instruction
    // again, the memory may be mapped and undefined behavior would occur rather than repeating
    // the segfault. So we simply abort here.
    posix.abort();
}

fn dumpSegfaultInfoPosix(sig: i32, code: i32, addr: usize, ctx_ptr: ?*anyopaque) void {
    const stderr = lockStderrWriter(&.{});
    defer unlockStderrWriter();
    _ = switch (sig) {
        posix.SIG.SEGV => if (native_arch == .x86_64 and native_os == .linux and code == 128) // SI_KERNEL
            // x86_64 doesn't have a full 64-bit virtual address space.
            // Addresses outside of that address space are non-canonical
            // and the CPU won't provide the faulting address to us.
            // This happens when accessing memory addresses such as 0xaaaaaaaaaaaaaaaa
            // but can also happen when no addressable memory is involved;
            // for example when reading/writing model-specific registers
            // by executing `rdmsr` or `wrmsr` in user-space (unprivileged mode).
            stderr.writeAll("General protection exception (no address available)\n")
        else
            stderr.print("Segmentation fault at address 0x{x}\n", .{addr}),
        posix.SIG.ILL => stderr.print("Illegal instruction at address 0x{x}\n", .{addr}),
        posix.SIG.BUS => stderr.print("Bus error at address 0x{x}\n", .{addr}),
        posix.SIG.FPE => stderr.print("Arithmetic exception at address 0x{x}\n", .{addr}),
        else => unreachable,
    } catch posix.abort();

    switch (native_arch) {
        .x86,
        .x86_64,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        .aarch64,
        .aarch64_be,
        => {
            // Some kernels don't align `ctx_ptr` properly. Handle this defensively.
            const ctx: *align(1) posix.ucontext_t = @ptrCast(ctx_ptr);
            var new_ctx: posix.ucontext_t = ctx.*;
            if (builtin.os.tag.isDarwin() and builtin.cpu.arch == .aarch64) {
                // The kernel incorrectly writes the contents of `__mcontext_data` right after `mcontext`,
                // rather than after the 8 bytes of padding that are supposed to sit between the two. Copy the
                // contents to the right place so that the `mcontext` pointer will be correct after the
                // `relocateContext` call below.
                new_ctx.__mcontext_data = @as(*align(1) extern struct {
                    onstack: c_int,
                    sigmask: std.c.sigset_t,
                    stack: std.c.stack_t,
                    link: ?*std.c.ucontext_t,
                    mcsize: u64,
                    mcontext: *std.c.mcontext_t,
                    __mcontext_data: std.c.mcontext_t align(@sizeOf(usize)), // Disable padding after `mcontext`.
                }, @ptrCast(ctx)).__mcontext_data;
            }
            relocateContext(&new_ctx);
            dumpStackTraceFromBase(&new_ctx, stderr);
        },
        else => {},
    }
}

fn handleSegfaultWindows(info: *windows.EXCEPTION_POINTERS) callconv(.winapi) c_long {
    switch (info.ExceptionRecord.ExceptionCode) {
        windows.EXCEPTION_DATATYPE_MISALIGNMENT => handleSegfaultWindowsExtra(info, 0, "Unaligned Memory Access"),
        windows.EXCEPTION_ACCESS_VIOLATION => handleSegfaultWindowsExtra(info, 1, null),
        windows.EXCEPTION_ILLEGAL_INSTRUCTION => handleSegfaultWindowsExtra(info, 2, null),
        windows.EXCEPTION_STACK_OVERFLOW => handleSegfaultWindowsExtra(info, 0, "Stack Overflow"),
        else => return windows.EXCEPTION_CONTINUE_SEARCH,
    }
}

fn handleSegfaultWindowsExtra(info: *windows.EXCEPTION_POINTERS, msg: u8, label: ?[]const u8) noreturn {
    // For backends that cannot handle the language features used by this segfault handler, we have a simpler one,
    switch (builtin.zig_backend) {
        .stage2_x86_64 => if (builtin.target.ofmt == .coff) @trap(),
        else => {},
    }

    comptime assert(windows.CONTEXT != void);
    nosuspend switch (panic_stage) {
        0 => {
            panic_stage = 1;
            _ = panicking.fetchAdd(1, .seq_cst);

            {
                const stderr = lockStderrWriter(&.{});
                defer unlockStderrWriter();

                dumpSegfaultInfoWindows(info, msg, label, stderr);
            }

            waitForOtherThreadToFinishPanicking();
        },
        1 => {
            panic_stage = 2;
            fs.File.stderr().writeAll("aborting due to recursive panic\n") catch {};
        },
        else => {},
    };
    posix.abort();
}

fn dumpSegfaultInfoWindows(info: *windows.EXCEPTION_POINTERS, msg: u8, label: ?[]const u8, stderr: *Writer) void {
    _ = switch (msg) {
        0 => stderr.print("{s}\n", .{label.?}),
        1 => stderr.print("Segmentation fault at address 0x{x}\n", .{info.ExceptionRecord.ExceptionInformation[1]}),
        2 => stderr.print("Illegal instruction at address 0x{x}\n", .{info.ContextRecord.getRegs().ip}),
        else => unreachable,
    } catch posix.abort();

    dumpStackTraceFromBase(info.ContextRecord, stderr);
}

pub fn dumpStackPointerAddr(prefix: []const u8) void {
    const sp = asm (""
        : [argc] "={rsp}" (-> usize),
    );
    print("{s} sp = 0x{x}\n", .{ prefix, sp });
}

test "manage resources correctly" {
    if (builtin.strip_debug_info) return error.SkipZigTest;

    if (native_os == .wasi) return error.SkipZigTest;

    if (native_os == .windows) {
        // https://github.com/ziglang/zig/issues/13963
        return error.SkipZigTest;
    }

    // self-hosted debug info is still too buggy
    if (builtin.zig_backend != .stage2_llvm) return error.SkipZigTest;

    var discarding: std.io.Writer.Discarding = .init(&.{});
    var di = try SelfInfo.open(testing.allocator);
    defer di.deinit();
    try printSourceAtAddress(&di, &discarding.writer, showMyTrace(), io.tty.detectConfig(.stderr()));
}

noinline fn showMyTrace() usize {
    return @returnAddress();
}

/// This API helps you track where a value originated and where it was mutated,
/// or any other points of interest.
/// In debug mode, it adds a small size penalty (104 bytes on 64-bit architectures)
/// to the aggregate that you add it to.
/// In release mode, it is size 0 and all methods are no-ops.
/// This is a pre-made type with default settings.
/// For more advanced usage, see `ConfigurableTrace`.
pub const Trace = ConfigurableTrace(2, 4, builtin.mode == .Debug);

pub fn ConfigurableTrace(comptime size: usize, comptime stack_frame_count: usize, comptime is_enabled: bool) type {
    return struct {
        addrs: [actual_size][stack_frame_count]usize,
        notes: [actual_size][]const u8,
        index: Index,

        const actual_size = if (enabled) size else 0;
        const Index = if (enabled) usize else u0;

        pub const init: @This() = .{
            .addrs = undefined,
            .notes = undefined,
            .index = 0,
        };

        pub const enabled = is_enabled;

        pub const add = if (enabled) addNoInline else addNoOp;

        pub noinline fn addNoInline(t: *@This(), note: []const u8) void {
            comptime assert(enabled);
            return addAddr(t, @returnAddress(), note);
        }

        pub inline fn addNoOp(t: *@This(), note: []const u8) void {
            _ = t;
            _ = note;
            comptime assert(!enabled);
        }

        pub fn addAddr(t: *@This(), addr: usize, note: []const u8) void {
            if (!enabled) return;

            if (t.index < size) {
                t.notes[t.index] = note;
                t.addrs[t.index] = [1]usize{0} ** stack_frame_count;
                var stack_trace: std.builtin.StackTrace = .{
                    .index = 0,
                    .instruction_addresses = &t.addrs[t.index],
                };
                captureStackTrace(addr, &stack_trace);
            }
            // Keep counting even if the end is reached so that the
            // user can find out how much more size they need.
            t.index += 1;
        }

        pub fn dump(t: @This()) void {
            if (!enabled) return;

            const tty_config = io.tty.detectConfig(.stderr());
            const stderr = lockStderrWriter(&.{});
            defer unlockStderrWriter();
            const end = @min(t.index, size);
            const debug_info = getSelfDebugInfo() catch |err| {
                stderr.print(
                    "Unable to dump stack trace: Unable to open debug info: {s}\n",
                    .{@errorName(err)},
                ) catch return;
                return;
            };
            for (t.addrs[0..end], 0..) |frames_array, i| {
                stderr.print("{s}:\n", .{t.notes[i]}) catch return;
                var frames_array_mutable = frames_array;
                const frames = mem.sliceTo(frames_array_mutable[0..], 0);
                const stack_trace: std.builtin.StackTrace = .{
                    .index = frames.len,
                    .instruction_addresses = frames,
                };
                writeStackTrace(stack_trace, stderr, debug_info, tty_config) catch continue;
            }
            if (t.index > end) {
                stderr.print("{d} more traces not shown; consider increasing trace size\n", .{
                    t.index - end,
                }) catch return;
            }
        }

        pub fn format(
            t: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: *Writer,
        ) !void {
            if (fmt.len != 0) std.fmt.invalidFmtError(fmt, t);
            _ = options;
            if (enabled) {
                try writer.writeAll("\n");
                t.dump();
                try writer.writeAll("\n");
            } else {
                return writer.writeAll("(value tracing disabled)");
            }
        }
    };
}

pub const SafetyLock = struct {
    state: State = if (runtime_safety) .unlocked else .unknown,

    pub const State = if (runtime_safety) enum { unlocked, locked } else enum { unknown };

    pub fn lock(l: *SafetyLock) void {
        if (!runtime_safety) return;
        assert(l.state == .unlocked);
        l.state = .locked;
    }

    pub fn unlock(l: *SafetyLock) void {
        if (!runtime_safety) return;
        assert(l.state == .locked);
        l.state = .unlocked;
    }

    pub fn assertUnlocked(l: SafetyLock) void {
        if (!runtime_safety) return;
        assert(l.state == .unlocked);
    }

    pub fn assertLocked(l: SafetyLock) void {
        if (!runtime_safety) return;
        assert(l.state == .locked);
    }
};

test SafetyLock {
    var safety_lock: SafetyLock = .{};
    safety_lock.assertUnlocked();
    safety_lock.lock();
    safety_lock.assertLocked();
    safety_lock.unlock();
    safety_lock.assertUnlocked();
}

/// Detect whether the program is being executed in the Valgrind virtual machine.
///
/// When Valgrind integrations are disabled, this returns comptime-known false.
/// Otherwise, the result is runtime-known.
pub inline fn inValgrind() bool {
    if (@inComptime()) return false;
    if (!builtin.valgrind_support) return false;
    return std.valgrind.runningOnValgrind() > 0;
}

test {
    _ = &Dwarf;
    _ = &MemoryAccessor;
    _ = &FixedBufferReader;
    _ = &Pdb;
    _ = &SelfInfo;
    _ = &dumpHex;
}
