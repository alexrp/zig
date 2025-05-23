//! Contains only the definition of `io_uring_sqe`.
//! Split into its own file to compartmentalize the initialization methods.

const std = @import("../../std.zig");
const linux = std.os.linux;

pub const io_uring_sqe = extern struct {
    opcode: linux.IORING_OP,
    flags: u8,
    ioprio: u16,
    fd: i32,
    off: u64,
    addr: u64,
    len: u32,
    rw_flags: u32,
    user_data: u64,
    buf_index: u16,
    personality: u16,
    splice_fd_in: i32,
    addr3: u64,
    resv: u64,

    pub fn prep_nop(sqe: *linux.io_uring_sqe) void {
        sqe.* = .{
            .opcode = .NOP,
            .flags = 0,
            .ioprio = 0,
            .fd = 0,
            .off = 0,
            .addr = 0,
            .len = 0,
            .rw_flags = 0,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_fsync(sqe: *linux.io_uring_sqe, fd: linux.fd_t, flags: u32) void {
        sqe.* = .{
            .opcode = .FSYNC,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = 0,
            .addr = 0,
            .len = 0,
            .rw_flags = flags,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_rw(
        sqe: *linux.io_uring_sqe,
        op: linux.IORING_OP,
        fd: linux.fd_t,
        addr: u64,
        len: usize,
        offset: u64,
    ) void {
        sqe.* = .{
            .opcode = op,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = offset,
            .addr = addr,
            .len = @intCast(len),
            .rw_flags = 0,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_read(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []u8, offset: u64) void {
        sqe.prep_rw(.READ, fd, @intFromPtr(buffer.ptr), buffer.len, offset);
    }

    pub fn prep_write(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []const u8, offset: u64) void {
        sqe.prep_rw(.WRITE, fd, @intFromPtr(buffer.ptr), buffer.len, offset);
    }

    pub fn prep_splice(sqe: *linux.io_uring_sqe, fd_in: linux.fd_t, off_in: u64, fd_out: linux.fd_t, off_out: u64, len: usize) void {
        sqe.prep_rw(.SPLICE, fd_out, undefined, len, off_out);
        sqe.addr = off_in;
        sqe.splice_fd_in = fd_in;
    }

    pub fn prep_readv(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        iovecs: []const std.posix.iovec,
        offset: u64,
    ) void {
        sqe.prep_rw(.READV, fd, @intFromPtr(iovecs.ptr), iovecs.len, offset);
    }

    pub fn prep_writev(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        iovecs: []const std.posix.iovec_const,
        offset: u64,
    ) void {
        sqe.prep_rw(.WRITEV, fd, @intFromPtr(iovecs.ptr), iovecs.len, offset);
    }

    pub fn prep_read_fixed(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: *std.posix.iovec, offset: u64, buffer_index: u16) void {
        sqe.prep_rw(.READ_FIXED, fd, @intFromPtr(buffer.base), buffer.len, offset);
        sqe.buf_index = buffer_index;
    }

    pub fn prep_write_fixed(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: *std.posix.iovec, offset: u64, buffer_index: u16) void {
        sqe.prep_rw(.WRITE_FIXED, fd, @intFromPtr(buffer.base), buffer.len, offset);
        sqe.buf_index = buffer_index;
    }

    pub fn prep_accept(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: ?*linux.sockaddr,
        addrlen: ?*linux.socklen_t,
        flags: u32,
    ) void {
        // `addr` holds a pointer to `sockaddr`, and `addr2` holds a pointer to socklen_t`.
        // `addr2` maps to `sqe.off` (u64) instead of `sqe.len` (which is only a u32).
        sqe.prep_rw(.ACCEPT, fd, @intFromPtr(addr), 0, @intFromPtr(addrlen));
        sqe.rw_flags = flags;
    }

    pub fn prep_accept_direct(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: ?*linux.sockaddr,
        addrlen: ?*linux.socklen_t,
        flags: u32,
        file_index: u32,
    ) void {
        prep_accept(sqe, fd, addr, addrlen, flags);
        __io_uring_set_target_fixed_file(sqe, file_index);
    }

    pub fn prep_multishot_accept_direct(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: ?*linux.sockaddr,
        addrlen: ?*linux.socklen_t,
        flags: u32,
    ) void {
        prep_multishot_accept(sqe, fd, addr, addrlen, flags);
        __io_uring_set_target_fixed_file(sqe, linux.IORING_FILE_INDEX_ALLOC);
    }

    fn __io_uring_set_target_fixed_file(sqe: *linux.io_uring_sqe, file_index: u32) void {
        const sqe_file_index: u32 = if (file_index == linux.IORING_FILE_INDEX_ALLOC)
            linux.IORING_FILE_INDEX_ALLOC
        else
            // 0 means no fixed files, indexes should be encoded as "index + 1"
            file_index + 1;
        // This filed is overloaded in liburing:
        //   splice_fd_in: i32
        //   sqe_file_index: u32
        sqe.splice_fd_in = @bitCast(sqe_file_index);
    }

    pub fn prep_connect(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: *const linux.sockaddr,
        addrlen: linux.socklen_t,
    ) void {
        // `addrlen` maps to `sqe.off` (u64) instead of `sqe.len` (which is only a u32).
        sqe.prep_rw(.CONNECT, fd, @intFromPtr(addr), 0, addrlen);
    }

    pub fn prep_epoll_ctl(
        sqe: *linux.io_uring_sqe,
        epfd: linux.fd_t,
        fd: linux.fd_t,
        op: u32,
        ev: ?*linux.epoll_event,
    ) void {
        sqe.prep_rw(.EPOLL_CTL, epfd, @intFromPtr(ev), op, @intCast(fd));
    }

    pub fn prep_recv(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []u8, flags: u32) void {
        sqe.prep_rw(.RECV, fd, @intFromPtr(buffer.ptr), buffer.len, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_recv_multishot(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        buffer: []u8,
        flags: u32,
    ) void {
        sqe.prep_recv(fd, buffer, flags);
        sqe.ioprio |= linux.IORING_RECV_MULTISHOT;
    }

    pub fn prep_recvmsg(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        msg: *linux.msghdr,
        flags: u32,
    ) void {
        sqe.prep_rw(.RECVMSG, fd, @intFromPtr(msg), 1, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_recvmsg_multishot(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        msg: *linux.msghdr,
        flags: u32,
    ) void {
        sqe.prep_recvmsg(fd, msg, flags);
        sqe.ioprio |= linux.IORING_RECV_MULTISHOT;
    }

    pub fn prep_send(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []const u8, flags: u32) void {
        sqe.prep_rw(.SEND, fd, @intFromPtr(buffer.ptr), buffer.len, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_send_zc(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []const u8, flags: u32, zc_flags: u16) void {
        sqe.prep_rw(.SEND_ZC, fd, @intFromPtr(buffer.ptr), buffer.len, 0);
        sqe.rw_flags = flags;
        sqe.ioprio = zc_flags;
    }

    pub fn prep_send_zc_fixed(sqe: *linux.io_uring_sqe, fd: linux.fd_t, buffer: []const u8, flags: u32, zc_flags: u16, buf_index: u16) void {
        prep_send_zc(sqe, fd, buffer, flags, zc_flags);
        sqe.ioprio |= linux.IORING_RECVSEND_FIXED_BUF;
        sqe.buf_index = buf_index;
    }

    pub fn prep_sendmsg_zc(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        msg: *const linux.msghdr_const,
        flags: u32,
    ) void {
        prep_sendmsg(sqe, fd, msg, flags);
        sqe.opcode = .SENDMSG_ZC;
    }

    pub fn prep_sendmsg(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        msg: *const linux.msghdr_const,
        flags: u32,
    ) void {
        sqe.prep_rw(.SENDMSG, fd, @intFromPtr(msg), 1, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_openat(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        path: [*:0]const u8,
        flags: linux.O,
        mode: linux.mode_t,
    ) void {
        sqe.prep_rw(.OPENAT, fd, @intFromPtr(path), mode, 0);
        sqe.rw_flags = @bitCast(flags);
    }

    pub fn prep_openat_direct(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        path: [*:0]const u8,
        flags: linux.O,
        mode: linux.mode_t,
        file_index: u32,
    ) void {
        prep_openat(sqe, fd, path, flags, mode);
        __io_uring_set_target_fixed_file(sqe, file_index);
    }

    pub fn prep_close(sqe: *linux.io_uring_sqe, fd: linux.fd_t) void {
        sqe.* = .{
            .opcode = .CLOSE,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = 0,
            .addr = 0,
            .len = 0,
            .rw_flags = 0,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_close_direct(sqe: *linux.io_uring_sqe, file_index: u32) void {
        prep_close(sqe, 0);
        __io_uring_set_target_fixed_file(sqe, file_index);
    }

    pub fn prep_timeout(
        sqe: *linux.io_uring_sqe,
        ts: *const linux.kernel_timespec,
        count: u32,
        flags: u32,
    ) void {
        sqe.prep_rw(.TIMEOUT, -1, @intFromPtr(ts), 1, count);
        sqe.rw_flags = flags;
    }

    pub fn prep_timeout_remove(sqe: *linux.io_uring_sqe, timeout_user_data: u64, flags: u32) void {
        sqe.* = .{
            .opcode = .TIMEOUT_REMOVE,
            .flags = 0,
            .ioprio = 0,
            .fd = -1,
            .off = 0,
            .addr = timeout_user_data,
            .len = 0,
            .rw_flags = flags,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_link_timeout(
        sqe: *linux.io_uring_sqe,
        ts: *const linux.kernel_timespec,
        flags: u32,
    ) void {
        sqe.prep_rw(.LINK_TIMEOUT, -1, @intFromPtr(ts), 1, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_poll_add(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        poll_mask: u32,
    ) void {
        sqe.prep_rw(.POLL_ADD, fd, @intFromPtr(@as(?*anyopaque, null)), 0, 0);
        // Poll masks previously used to comprise of 16 bits in the flags union of
        // a SQE, but were then extended to comprise of 32 bits in order to make
        // room for additional option flags. To ensure that the correct bits of
        // poll masks are consistently and properly read across multiple kernel
        // versions, poll masks are enforced to be little-endian.
        // https://www.spinics.net/lists/io-uring/msg02848.html
        sqe.rw_flags = std.mem.nativeToLittle(u32, poll_mask);
    }

    pub fn prep_poll_remove(
        sqe: *linux.io_uring_sqe,
        target_user_data: u64,
    ) void {
        sqe.prep_rw(.POLL_REMOVE, -1, target_user_data, 0, 0);
    }

    pub fn prep_poll_update(
        sqe: *linux.io_uring_sqe,
        old_user_data: u64,
        new_user_data: u64,
        poll_mask: u32,
        flags: u32,
    ) void {
        sqe.prep_rw(.POLL_REMOVE, -1, old_user_data, flags, new_user_data);
        // Poll masks previously used to comprise of 16 bits in the flags union of
        // a SQE, but were then extended to comprise of 32 bits in order to make
        // room for additional option flags. To ensure that the correct bits of
        // poll masks are consistently and properly read across multiple kernel
        // versions, poll masks are enforced to be little-endian.
        // https://www.spinics.net/lists/io-uring/msg02848.html
        sqe.rw_flags = std.mem.nativeToLittle(u32, poll_mask);
    }

    pub fn prep_fallocate(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        mode: i32,
        offset: u64,
        len: u64,
    ) void {
        sqe.* = .{
            .opcode = .FALLOCATE,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = offset,
            .addr = len,
            .len = @intCast(mode),
            .rw_flags = 0,
            .user_data = 0,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }

    pub fn prep_statx(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        path: [*:0]const u8,
        flags: u32,
        mask: u32,
        buf: *linux.Statx,
    ) void {
        sqe.prep_rw(.STATX, fd, @intFromPtr(path), mask, @intFromPtr(buf));
        sqe.rw_flags = flags;
    }

    pub fn prep_cancel(
        sqe: *linux.io_uring_sqe,
        cancel_user_data: u64,
        flags: u32,
    ) void {
        sqe.prep_rw(.ASYNC_CANCEL, -1, cancel_user_data, 0, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_cancel_fd(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        flags: u32,
    ) void {
        sqe.prep_rw(.ASYNC_CANCEL, fd, 0, 0, 0);
        sqe.rw_flags = flags | linux.IORING_ASYNC_CANCEL_FD;
    }

    pub fn prep_shutdown(
        sqe: *linux.io_uring_sqe,
        sockfd: linux.socket_t,
        how: u32,
    ) void {
        sqe.prep_rw(.SHUTDOWN, sockfd, 0, how, 0);
    }

    pub fn prep_renameat(
        sqe: *linux.io_uring_sqe,
        old_dir_fd: linux.fd_t,
        old_path: [*:0]const u8,
        new_dir_fd: linux.fd_t,
        new_path: [*:0]const u8,
        flags: u32,
    ) void {
        sqe.prep_rw(
            .RENAMEAT,
            old_dir_fd,
            @intFromPtr(old_path),
            0,
            @intFromPtr(new_path),
        );
        sqe.len = @bitCast(new_dir_fd);
        sqe.rw_flags = flags;
    }

    pub fn prep_unlinkat(
        sqe: *linux.io_uring_sqe,
        dir_fd: linux.fd_t,
        path: [*:0]const u8,
        flags: u32,
    ) void {
        sqe.prep_rw(.UNLINKAT, dir_fd, @intFromPtr(path), 0, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_mkdirat(
        sqe: *linux.io_uring_sqe,
        dir_fd: linux.fd_t,
        path: [*:0]const u8,
        mode: linux.mode_t,
    ) void {
        sqe.prep_rw(.MKDIRAT, dir_fd, @intFromPtr(path), mode, 0);
    }

    pub fn prep_symlinkat(
        sqe: *linux.io_uring_sqe,
        target: [*:0]const u8,
        new_dir_fd: linux.fd_t,
        link_path: [*:0]const u8,
    ) void {
        sqe.prep_rw(
            .SYMLINKAT,
            new_dir_fd,
            @intFromPtr(target),
            0,
            @intFromPtr(link_path),
        );
    }

    pub fn prep_linkat(
        sqe: *linux.io_uring_sqe,
        old_dir_fd: linux.fd_t,
        old_path: [*:0]const u8,
        new_dir_fd: linux.fd_t,
        new_path: [*:0]const u8,
        flags: u32,
    ) void {
        sqe.prep_rw(
            .LINKAT,
            old_dir_fd,
            @intFromPtr(old_path),
            0,
            @intFromPtr(new_path),
        );
        sqe.len = @bitCast(new_dir_fd);
        sqe.rw_flags = flags;
    }

    pub fn prep_files_update(
        sqe: *linux.io_uring_sqe,
        fds: []const linux.fd_t,
        offset: u32,
    ) void {
        sqe.prep_rw(.FILES_UPDATE, -1, @intFromPtr(fds.ptr), fds.len, @intCast(offset));
    }

    pub fn prep_files_update_alloc(
        sqe: *linux.io_uring_sqe,
        fds: []linux.fd_t,
    ) void {
        sqe.prep_rw(.FILES_UPDATE, -1, @intFromPtr(fds.ptr), fds.len, linux.IORING_FILE_INDEX_ALLOC);
    }

    pub fn prep_provide_buffers(
        sqe: *linux.io_uring_sqe,
        buffers: [*]u8,
        buffer_len: usize,
        num: usize,
        group_id: usize,
        buffer_id: usize,
    ) void {
        const ptr = @intFromPtr(buffers);
        sqe.prep_rw(.PROVIDE_BUFFERS, @intCast(num), ptr, buffer_len, buffer_id);
        sqe.buf_index = @intCast(group_id);
    }

    pub fn prep_remove_buffers(
        sqe: *linux.io_uring_sqe,
        num: usize,
        group_id: usize,
    ) void {
        sqe.prep_rw(.REMOVE_BUFFERS, @intCast(num), 0, 0, 0);
        sqe.buf_index = @intCast(group_id);
    }

    pub fn prep_multishot_accept(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: ?*linux.sockaddr,
        addrlen: ?*linux.socklen_t,
        flags: u32,
    ) void {
        prep_accept(sqe, fd, addr, addrlen, flags);
        sqe.ioprio |= linux.IORING_ACCEPT_MULTISHOT;
    }

    pub fn prep_socket(
        sqe: *linux.io_uring_sqe,
        domain: u32,
        socket_type: u32,
        protocol: u32,
        flags: u32,
    ) void {
        sqe.prep_rw(.SOCKET, @intCast(domain), 0, protocol, socket_type);
        sqe.rw_flags = flags;
    }

    pub fn prep_socket_direct(
        sqe: *linux.io_uring_sqe,
        domain: u32,
        socket_type: u32,
        protocol: u32,
        flags: u32,
        file_index: u32,
    ) void {
        prep_socket(sqe, domain, socket_type, protocol, flags);
        __io_uring_set_target_fixed_file(sqe, file_index);
    }

    pub fn prep_socket_direct_alloc(
        sqe: *linux.io_uring_sqe,
        domain: u32,
        socket_type: u32,
        protocol: u32,
        flags: u32,
    ) void {
        prep_socket(sqe, domain, socket_type, protocol, flags);
        __io_uring_set_target_fixed_file(sqe, linux.IORING_FILE_INDEX_ALLOC);
    }

    pub fn prep_waitid(
        sqe: *linux.io_uring_sqe,
        id_type: linux.P,
        id: i32,
        infop: *linux.siginfo_t,
        options: u32,
        flags: u32,
    ) void {
        sqe.prep_rw(.WAITID, id, 0, @intFromEnum(id_type), @intFromPtr(infop));
        sqe.rw_flags = flags;
        sqe.splice_fd_in = @bitCast(options);
    }

    pub fn prep_bind(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        addr: *const linux.sockaddr,
        addrlen: linux.socklen_t,
        flags: u32,
    ) void {
        sqe.prep_rw(.BIND, fd, @intFromPtr(addr), 0, addrlen);
        sqe.rw_flags = flags;
    }

    pub fn prep_listen(
        sqe: *linux.io_uring_sqe,
        fd: linux.fd_t,
        backlog: usize,
        flags: u32,
    ) void {
        sqe.prep_rw(.LISTEN, fd, 0, backlog, 0);
        sqe.rw_flags = flags;
    }

    pub fn prep_cmd_sock(
        sqe: *linux.io_uring_sqe,
        cmd_op: linux.IO_URING_SOCKET_OP,
        fd: linux.fd_t,
        level: u32,
        optname: u32,
        optval: u64,
        optlen: u32,
    ) void {
        sqe.prep_rw(.URING_CMD, fd, 0, 0, 0);
        // off is overloaded with cmd_op, https://github.com/axboe/liburing/blob/e1003e496e66f9b0ae06674869795edf772d5500/src/include/liburing/io_uring.h#L39
        sqe.off = @intFromEnum(cmd_op);
        // addr is overloaded, https://github.com/axboe/liburing/blob/e1003e496e66f9b0ae06674869795edf772d5500/src/include/liburing/io_uring.h#L46
        sqe.addr = @bitCast(packed struct {
            level: u32,
            optname: u32,
        }{
            .level = level,
            .optname = optname,
        });
        // splice_fd_in if overloaded u32 -> i32
        sqe.splice_fd_in = @bitCast(optlen);
        // addr3 is overloaded, https://github.com/axboe/liburing/blob/e1003e496e66f9b0ae06674869795edf772d5500/src/include/liburing/io_uring.h#L102
        sqe.addr3 = optval;
    }

    pub fn set_flags(sqe: *linux.io_uring_sqe, flags: u8) void {
        sqe.flags |= flags;
    }

    /// This SQE forms a link with the next SQE in the submission ring. Next SQE
    /// will not be started before this one completes. Forms a chain of SQEs.
    pub fn link_next(sqe: *linux.io_uring_sqe) void {
        sqe.flags |= linux.IOSQE_IO_LINK;
    }
};
