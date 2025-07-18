const Tokenizer = @This();

index: usize = 0,
bytes: []const u8,
state: State = .lhs,

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn next(self: *Tokenizer) ?Token {
    var start = self.index;
    var must_resolve = false;
    while (self.index < self.bytes.len) {
        const char = self.bytes[self.index];
        switch (self.state) {
            .lhs => switch (char) {
                '\t', '\n', '\r', ' ' => {
                    // silently ignore whitespace
                    self.index += 1;
                },
                else => {
                    start = self.index;
                    self.state = .target;
                },
            },
            .target => switch (char) {
                '\n', '\r' => {
                    return errorIllegalChar(.invalid_target, self.index, char);
                },
                '$' => {
                    self.state = .target_dollar_sign;
                    self.index += 1;
                },
                '\\' => {
                    self.state = .target_reverse_solidus;
                    self.index += 1;
                },
                ':' => {
                    self.state = .target_colon;
                    self.index += 1;
                },
                '\t', ' ' => {
                    self.state = .target_space;

                    const bytes = self.bytes[start..self.index];
                    std.debug.assert(bytes.len != 0);
                    self.index += 1;

                    return finishTarget(must_resolve, bytes);
                },
                else => {
                    self.index += 1;
                },
            },
            .target_reverse_solidus => switch (char) {
                '\t', '\n', '\r' => {
                    return errorIllegalChar(.bad_target_escape, self.index, char);
                },
                ' ', '#', '\\' => {
                    must_resolve = true;
                    self.state = .target;
                    self.index += 1;
                },
                '$' => {
                    self.state = .target_dollar_sign;
                    self.index += 1;
                },
                else => {
                    self.state = .target;
                    self.index += 1;
                },
            },
            .target_dollar_sign => switch (char) {
                '$' => {
                    must_resolve = true;
                    self.state = .target;
                    self.index += 1;
                },
                else => {
                    return errorIllegalChar(.expected_dollar_sign, self.index, char);
                },
            },
            .target_colon => switch (char) {
                '\n', '\r' => {
                    const bytes = self.bytes[start .. self.index - 1];
                    if (bytes.len != 0) {
                        self.state = .lhs;
                        return finishTarget(must_resolve, bytes);
                    }
                    // silently ignore null target
                    self.state = .lhs;
                },
                '/', '\\' => {
                    self.state = .target_colon_reverse_solidus;
                    self.index += 1;
                },
                else => {
                    const bytes = self.bytes[start .. self.index - 1];
                    if (bytes.len != 0) {
                        self.state = .rhs;
                        return finishTarget(must_resolve, bytes);
                    }
                    // silently ignore null target
                    self.state = .lhs;
                },
            },
            .target_colon_reverse_solidus => switch (char) {
                '\n', '\r' => {
                    const bytes = self.bytes[start .. self.index - 2];
                    if (bytes.len != 0) {
                        self.state = .lhs;
                        return finishTarget(must_resolve, bytes);
                    }
                    // silently ignore null target
                    self.state = .lhs;
                },
                else => {
                    self.state = .target;
                },
            },
            .target_space => switch (char) {
                '\t', ' ' => {
                    // silently ignore additional horizontal whitespace
                    self.index += 1;
                },
                ':' => {
                    self.state = .rhs;
                    self.index += 1;
                },
                else => {
                    return errorIllegalChar(.expected_colon, self.index, char);
                },
            },
            .rhs => switch (char) {
                '\t', ' ' => {
                    // silently ignore horizontal whitespace
                    self.index += 1;
                },
                '\n', '\r' => {
                    self.state = .lhs;
                },
                '\\' => {
                    self.state = .rhs_continuation;
                    self.index += 1;
                },
                '"' => {
                    self.state = .prereq_quote;
                    self.index += 1;
                    start = self.index;
                },
                else => {
                    start = self.index;
                    self.state = .prereq;
                },
            },
            .rhs_continuation => switch (char) {
                '\n' => {
                    self.state = .rhs;
                    self.index += 1;
                },
                '\r' => {
                    self.state = .rhs_continuation_linefeed;
                    self.index += 1;
                },
                else => {
                    return errorIllegalChar(.continuation_eol, self.index, char);
                },
            },
            .rhs_continuation_linefeed => switch (char) {
                '\n' => {
                    self.state = .rhs;
                    self.index += 1;
                },
                else => {
                    return errorIllegalChar(.continuation_eol, self.index, char);
                },
            },
            .prereq_quote => switch (char) {
                '"' => {
                    self.index += 1;
                    self.state = .rhs;
                    return finishPrereq(must_resolve, self.bytes[start .. self.index - 1]);
                },
                else => {
                    self.index += 1;
                },
            },
            .prereq => switch (char) {
                '\t', ' ' => {
                    self.state = .rhs;
                    return finishPrereq(must_resolve, self.bytes[start..self.index]);
                },
                '\n', '\r' => {
                    self.state = .lhs;
                    return finishPrereq(must_resolve, self.bytes[start..self.index]);
                },
                '\\' => {
                    self.state = .prereq_continuation;
                    self.index += 1;
                },
                else => {
                    self.index += 1;
                },
            },
            .prereq_continuation => switch (char) {
                '\n' => {
                    self.index += 1;
                    self.state = .rhs;
                    return finishPrereq(must_resolve, self.bytes[start .. self.index - 2]);
                },
                '\r' => {
                    self.state = .prereq_continuation_linefeed;
                    self.index += 1;
                },
                '\\' => {
                    // The previous \ wasn't a continuation, but this one might be.
                    self.index += 1;
                },
                ' ' => {
                    // not continuation, but escaped space must be resolved
                    must_resolve = true;
                    self.state = .prereq;
                    self.index += 1;
                },
                else => {
                    // not continuation
                    self.state = .prereq;
                    self.index += 1;
                },
            },
            .prereq_continuation_linefeed => switch (char) {
                '\n' => {
                    self.index += 1;
                    self.state = .rhs;
                    return finishPrereq(must_resolve, self.bytes[start .. self.index - 3]);
                },
                else => {
                    return errorIllegalChar(.continuation_eol, self.index, char);
                },
            },
        }
    } else {
        switch (self.state) {
            .lhs,
            .rhs,
            .rhs_continuation,
            .rhs_continuation_linefeed,
            => return null,
            .target => {
                return errorPosition(.incomplete_target, start, self.bytes[start..]);
            },
            .target_reverse_solidus,
            .target_dollar_sign,
            => {
                const idx = self.index - 1;
                return errorIllegalChar(.incomplete_escape, idx, self.bytes[idx]);
            },
            .target_colon => {
                const bytes = self.bytes[start .. self.index - 1];
                if (bytes.len != 0) {
                    self.index += 1;
                    self.state = .rhs;
                    return finishTarget(must_resolve, bytes);
                }
                // silently ignore null target
                self.state = .lhs;
                return null;
            },
            .target_colon_reverse_solidus => {
                const bytes = self.bytes[start .. self.index - 2];
                if (bytes.len != 0) {
                    self.index += 1;
                    self.state = .rhs;
                    return finishTarget(must_resolve, bytes);
                }
                // silently ignore null target
                self.state = .lhs;
                return null;
            },
            .target_space => {
                const idx = self.index - 1;
                return errorIllegalChar(.expected_colon, idx, self.bytes[idx]);
            },
            .prereq_quote => {
                return errorPosition(.incomplete_quoted_prerequisite, start, self.bytes[start..]);
            },
            .prereq => {
                self.state = .lhs;
                return finishPrereq(must_resolve, self.bytes[start..]);
            },
            .prereq_continuation => {
                self.state = .lhs;
                return finishPrereq(must_resolve, self.bytes[start .. self.index - 1]);
            },
            .prereq_continuation_linefeed => {
                self.state = .lhs;
                return finishPrereq(must_resolve, self.bytes[start .. self.index - 2]);
            },
        }
    }
    unreachable;
}

fn errorPosition(comptime id: std.meta.Tag(Token), index: usize, bytes: []const u8) Token {
    return @unionInit(Token, @tagName(id), .{ .index = index, .bytes = bytes });
}

fn errorIllegalChar(comptime id: std.meta.Tag(Token), index: usize, char: u8) Token {
    return @unionInit(Token, @tagName(id), .{ .index = index, .char = char });
}

fn finishTarget(must_resolve: bool, bytes: []const u8) Token {
    return if (must_resolve) .{ .target_must_resolve = bytes } else .{ .target = bytes };
}

fn finishPrereq(must_resolve: bool, bytes: []const u8) Token {
    return if (must_resolve) .{ .prereq_must_resolve = bytes } else .{ .prereq = bytes };
}

const State = enum {
    lhs,
    target,
    target_reverse_solidus,
    target_dollar_sign,
    target_colon,
    target_colon_reverse_solidus,
    target_space,
    rhs,
    rhs_continuation,
    rhs_continuation_linefeed,
    prereq_quote,
    prereq,
    prereq_continuation,
    prereq_continuation_linefeed,
};

pub const Token = union(enum) {
    target: []const u8,
    target_must_resolve: []const u8,
    prereq: []const u8,
    prereq_must_resolve: []const u8,

    incomplete_quoted_prerequisite: IndexAndBytes,
    incomplete_target: IndexAndBytes,

    invalid_target: IndexAndChar,
    bad_target_escape: IndexAndChar,
    expected_dollar_sign: IndexAndChar,
    continuation_eol: IndexAndChar,
    incomplete_escape: IndexAndChar,
    expected_colon: IndexAndChar,

    pub const IndexAndChar = struct {
        index: usize,
        char: u8,
    };

    pub const IndexAndBytes = struct {
        index: usize,
        bytes: []const u8,
    };

    /// Resolve escapes in target or prereq. Only valid with .target_must_resolve or .prereq_must_resolve.
    pub fn resolve(self: Token, gpa: Allocator, list: *std.ArrayListUnmanaged(u8)) error{OutOfMemory}!void {
        switch (self) {
            .target_must_resolve => |bytes| {
                var state: enum { start, escape, dollar } = .start;
                for (bytes) |c| {
                    switch (state) {
                        .start => {
                            switch (c) {
                                '\\' => state = .escape,
                                '$' => state = .dollar,
                                else => try list.append(gpa, c),
                            }
                        },
                        .escape => {
                            switch (c) {
                                ' ', '#', '\\' => {},
                                '$' => {
                                    try list.append(gpa, '\\');
                                    state = .dollar;
                                    continue;
                                },
                                else => try list.append(gpa, '\\'),
                            }
                            try list.append(gpa, c);
                            state = .start;
                        },
                        .dollar => {
                            try list.append(gpa, '$');
                            switch (c) {
                                '$' => {},
                                else => try list.append(gpa, c),
                            }
                            state = .start;
                        },
                    }
                }
            },
            .prereq_must_resolve => |bytes| {
                var state: enum { start, escape } = .start;
                for (bytes) |c| {
                    switch (state) {
                        .start => {
                            switch (c) {
                                '\\' => state = .escape,
                                else => try list.append(gpa, c),
                            }
                        },
                        .escape => {
                            switch (c) {
                                ' ' => {},
                                '\\' => {
                                    try list.append(gpa, c);
                                    continue;
                                },
                                else => try list.append(gpa, '\\'),
                            }
                            try list.append(gpa, c);
                            state = .start;
                        },
                    }
                }
            },
            else => unreachable,
        }
    }

    pub fn printError(self: Token, gpa: Allocator, list: *std.ArrayListUnmanaged(u8)) error{OutOfMemory}!void {
        switch (self) {
            .target, .target_must_resolve, .prereq, .prereq_must_resolve => unreachable, // not an error
            .incomplete_quoted_prerequisite,
            .incomplete_target,
            => |index_and_bytes| {
                try list.print(gpa, "{s} '", .{self.errStr()});
                if (self == .incomplete_target) {
                    const tmp = Token{ .target_must_resolve = index_and_bytes.bytes };
                    try tmp.resolve(gpa, list);
                } else {
                    try printCharValues(gpa, list, index_and_bytes.bytes);
                }
                try list.print(gpa, "' at position {d}", .{index_and_bytes.index});
            },
            .invalid_target,
            .bad_target_escape,
            .expected_dollar_sign,
            .continuation_eol,
            .incomplete_escape,
            .expected_colon,
            => |index_and_char| {
                try list.appendSlice(gpa, "illegal char ");
                try printUnderstandableChar(gpa, list, index_and_char.char);
                try list.print(gpa, " at position {d}: {s}", .{ index_and_char.index, self.errStr() });
            },
        }
    }

    fn errStr(self: Token) []const u8 {
        return switch (self) {
            .target, .target_must_resolve, .prereq, .prereq_must_resolve => unreachable, // not an error
            .incomplete_quoted_prerequisite => "incomplete quoted prerequisite",
            .incomplete_target => "incomplete target",
            .invalid_target => "invalid target",
            .bad_target_escape => "bad target escape",
            .expected_dollar_sign => "expecting '$'",
            .continuation_eol => "continuation expecting end-of-line",
            .incomplete_escape => "incomplete escape",
            .expected_colon => "expecting ':'",
        };
    }
};

test "empty file" {
    try depTokenizer("", "");
}

test "empty whitespace" {
    try depTokenizer("\n", "");
    try depTokenizer("\r", "");
    try depTokenizer("\r\n", "");
    try depTokenizer(" ", "");
}

test "empty colon" {
    try depTokenizer(":", "");
    try depTokenizer("\n:", "");
    try depTokenizer("\r:", "");
    try depTokenizer("\r\n:", "");
    try depTokenizer(" :", "");
}

test "empty target" {
    try depTokenizer("foo.o:", "target = {foo.o}");
    try depTokenizer(
        \\foo.o:
        \\bar.o:
        \\abcd.o:
    ,
        \\target = {foo.o}
        \\target = {bar.o}
        \\target = {abcd.o}
    );
}

test "whitespace empty target" {
    try depTokenizer("\nfoo.o:", "target = {foo.o}");
    try depTokenizer("\rfoo.o:", "target = {foo.o}");
    try depTokenizer("\r\nfoo.o:", "target = {foo.o}");
    try depTokenizer(" foo.o:", "target = {foo.o}");
}

test "escape empty target" {
    try depTokenizer("\\ foo.o:", "target = { foo.o}");
    try depTokenizer("\\#foo.o:", "target = {#foo.o}");
    try depTokenizer("\\\\foo.o:", "target = {\\foo.o}");
    try depTokenizer("$$foo.o:", "target = {$foo.o}");
}

test "empty target linefeeds" {
    try depTokenizer("\n", "");
    try depTokenizer("\r\n", "");

    const expect = "target = {foo.o}";
    try depTokenizer(
        \\foo.o:
    , expect);
    try depTokenizer(
        \\foo.o:
        \\
    , expect);
    try depTokenizer(
        \\foo.o:
    , expect);
    try depTokenizer(
        \\foo.o:
        \\
    , expect);
}

test "empty target linefeeds + continuations" {
    const expect = "target = {foo.o}";
    try depTokenizer(
        \\foo.o:\
    , expect);
    try depTokenizer(
        \\foo.o:\
        \\
    , expect);
    try depTokenizer(
        \\foo.o:\
    , expect);
    try depTokenizer(
        \\foo.o:\
        \\
    , expect);
}

test "empty target linefeeds + hspace + continuations" {
    const expect = "target = {foo.o}";
    try depTokenizer(
        \\foo.o: \
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\
    , expect);
    try depTokenizer(
        \\foo.o: \
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\
    , expect);
}

test "empty target + hspace + colon" {
    const expect = "target = {foo.o}";

    try depTokenizer("foo.o :", expect);
    try depTokenizer("foo.o\t\t\t:", expect);
    try depTokenizer("foo.o \t \t :", expect);
    try depTokenizer("\r\nfoo.o :", expect);
    try depTokenizer(" foo.o :", expect);
}

test "prereq" {
    const expect =
        \\target = {foo.o}
        \\prereq = {foo.c}
    ;
    try depTokenizer("foo.o: foo.c", expect);
    try depTokenizer(
        \\foo.o: \
        \\foo.c
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\ foo.c
    , expect);
    try depTokenizer(
        \\foo.o:    \
        \\    foo.c
    , expect);
}

test "prereq continuation" {
    const expect =
        \\target = {foo.o}
        \\prereq = {foo.h}
        \\prereq = {bar.h}
    ;
    try depTokenizer(
        \\foo.o: foo.h\
        \\bar.h
    , expect);
    try depTokenizer(
        \\foo.o: foo.h\
        \\bar.h
    , expect);
}

test "prereq continuation (CRLF)" {
    const expect =
        \\target = {foo.o}
        \\prereq = {foo.h}
        \\prereq = {bar.h}
    ;
    try depTokenizer("foo.o: foo.h\\\r\nbar.h", expect);
}

test "multiple prereqs" {
    const expect =
        \\target = {foo.o}
        \\prereq = {foo.c}
        \\prereq = {foo.h}
        \\prereq = {bar.h}
    ;
    try depTokenizer("foo.o: foo.c foo.h bar.h", expect);
    try depTokenizer(
        \\foo.o: \
        \\foo.c foo.h bar.h
    , expect);
    try depTokenizer(
        \\foo.o: foo.c foo.h bar.h\
    , expect);
    try depTokenizer(
        \\foo.o: foo.c foo.h bar.h\
        \\
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\foo.c       \
        \\     foo.h\
        \\bar.h
        \\
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\foo.c       \
        \\     foo.h\
        \\bar.h\
        \\
    , expect);
    try depTokenizer(
        \\foo.o: \
        \\foo.c       \
        \\     foo.h\
        \\bar.h\
    , expect);
}

test "multiple targets and prereqs" {
    try depTokenizer(
        \\foo.o: foo.c
        \\bar.o: bar.c a.h b.h c.h
        \\abc.o: abc.c \
        \\  one.h two.h \
        \\  three.h four.h
    ,
        \\target = {foo.o}
        \\prereq = {foo.c}
        \\target = {bar.o}
        \\prereq = {bar.c}
        \\prereq = {a.h}
        \\prereq = {b.h}
        \\prereq = {c.h}
        \\target = {abc.o}
        \\prereq = {abc.c}
        \\prereq = {one.h}
        \\prereq = {two.h}
        \\prereq = {three.h}
        \\prereq = {four.h}
    );
    try depTokenizer(
        \\ascii.o: ascii.c
        \\base64.o: base64.c stdio.h
        \\elf.o: elf.c a.h b.h c.h
        \\macho.o: \
        \\  macho.c\
        \\  a.h b.h c.h
    ,
        \\target = {ascii.o}
        \\prereq = {ascii.c}
        \\target = {base64.o}
        \\prereq = {base64.c}
        \\prereq = {stdio.h}
        \\target = {elf.o}
        \\prereq = {elf.c}
        \\prereq = {a.h}
        \\prereq = {b.h}
        \\prereq = {c.h}
        \\target = {macho.o}
        \\prereq = {macho.c}
        \\prereq = {a.h}
        \\prereq = {b.h}
        \\prereq = {c.h}
    );
    try depTokenizer(
        \\a$$scii.o: ascii.c
        \\\\base64.o: "\base64.c" "s t#dio.h"
        \\e\\lf.o: "e\lf.c" "a.h$$" "$$b.h c.h$$"
        \\macho.o: \
        \\  "macho!.c" \
        \\  a.h b.h c.h
    ,
        \\target = {a$scii.o}
        \\prereq = {ascii.c}
        \\target = {\base64.o}
        \\prereq = {\base64.c}
        \\prereq = {s t#dio.h}
        \\target = {e\lf.o}
        \\prereq = {e\lf.c}
        \\prereq = {a.h$$}
        \\prereq = {$$b.h c.h$$}
        \\target = {macho.o}
        \\prereq = {macho!.c}
        \\prereq = {a.h}
        \\prereq = {b.h}
        \\prereq = {c.h}
    );
}

test "windows quoted prereqs" {
    try depTokenizer(
        \\c:\foo.o: "C:\Program Files (x86)\Microsoft Visual Studio\foo.c"
        \\c:\foo2.o: "C:\Program Files (x86)\Microsoft Visual Studio\foo2.c" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\foo1.h" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\foo2.h"
    ,
        \\target = {c:\foo.o}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\foo.c}
        \\target = {c:\foo2.o}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\foo2.c}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\foo1.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\foo2.h}
    );
}

test "windows mixed prereqs" {
    try depTokenizer(
        \\cimport.o: \
        \\  C:\msys64\home\anon\project\zig\master\zig-cache\o\qhvhbUo7GU5iKyQ5mpA8TcQpncCYaQu0wwvr3ybiSTj_Dtqi1Nmcb70kfODJ2Qlg\cimport.h \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\stdio.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt.h" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vcruntime.h" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\sal.h" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\concurrencysal.h" \
        \\  C:\msys64\opt\zig\lib\zig\include\vadefs.h \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vadefs.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_wstdio.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_stdio_config.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\string.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_memory.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_memcpy_s.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\errno.h" \
        \\  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vcruntime_string.h" \
        \\  "C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_wstring.h"
    ,
        \\target = {cimport.o}
        \\prereq = {C:\msys64\home\anon\project\zig\master\zig-cache\o\qhvhbUo7GU5iKyQ5mpA8TcQpncCYaQu0wwvr3ybiSTj_Dtqi1Nmcb70kfODJ2Qlg\cimport.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\stdio.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vcruntime.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\sal.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\concurrencysal.h}
        \\prereq = {C:\msys64\opt\zig\lib\zig\include\vadefs.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vadefs.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_wstdio.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_stdio_config.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\string.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_memory.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_memcpy_s.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\errno.h}
        \\prereq = {C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.21.27702\lib\x64\\..\..\include\vcruntime_string.h}
        \\prereq = {C:\Program Files (x86)\Windows Kits\10\\Include\10.0.17763.0\ucrt\corecrt_wstring.h}
    );
}

test "windows funky targets" {
    try depTokenizer(
        \\C:\Users\anon\foo.o:
        \\C:\Users\anon\foo\ .o:
        \\C:\Users\anon\foo\#.o:
        \\C:\Users\anon\foo$$.o:
        \\C:\Users\anon\\\ foo.o:
        \\C:\Users\anon\\#foo.o:
        \\C:\Users\anon\$$foo.o:
        \\C:\Users\anon\\\ \ \ \ \ foo.o:
    ,
        \\target = {C:\Users\anon\foo.o}
        \\target = {C:\Users\anon\foo .o}
        \\target = {C:\Users\anon\foo#.o}
        \\target = {C:\Users\anon\foo$.o}
        \\target = {C:\Users\anon\ foo.o}
        \\target = {C:\Users\anon\#foo.o}
        \\target = {C:\Users\anon\$foo.o}
        \\target = {C:\Users\anon\     foo.o}
    );
}

test "windows funky prereqs" {
    // Note we don't support unquoted escaped spaces at the very beginning of a relative path
    // e.g. `\ SpaceAtTheBeginning.c`
    // This typically wouldn't be seen in the wild, since depfiles usually use absolute paths
    // and supporting it would degrade error messages for cases where it was meant to be a
    // continuation, but the line ending is missing.
    try depTokenizer(
        \\cimport.o: \
        \\  trailingbackslash\\
        \\  C:\Users\John\ Smith\AppData\Local\zig\p\1220d14057af1a9d6dde4643293527bd5ee5099517d655251a066666a4320737ea7c\cimport.c \
        \\  somedir\\ a.c\
        \\  somedir/\ a.c\
        \\  somedir\\ \ \ b.c\
        \\  somedir\\ \\ \c.c\
        \\
    ,
        \\target = {cimport.o}
        \\prereq = {trailingbackslash\}
        \\prereq = {C:\Users\John Smith\AppData\Local\zig\p\1220d14057af1a9d6dde4643293527bd5ee5099517d655251a066666a4320737ea7c\cimport.c}
        \\prereq = {somedir\ a.c}
        \\prereq = {somedir/ a.c}
        \\prereq = {somedir\   b.c}
        \\prereq = {somedir\ \ \c.c}
    );
}

test "windows drive and forward slashes" {
    try depTokenizer(
        \\C:/msys64/what/zig-cache\tmp\48ac4d78dd531abd-cxa_thread_atexit.obj: \
        \\  C:/msys64/opt/zig3/lib/zig/libc/mingw/crt/cxa_thread_atexit.c
    ,
        \\target = {C:/msys64/what/zig-cache\tmp\48ac4d78dd531abd-cxa_thread_atexit.obj}
        \\prereq = {C:/msys64/opt/zig3/lib/zig/libc/mingw/crt/cxa_thread_atexit.c}
    );
}

test "error incomplete escape - reverse_solidus" {
    try depTokenizer("\\",
        \\ERROR: illegal char '\' at position 0: incomplete escape
    );
    try depTokenizer("\t\\",
        \\ERROR: illegal char '\' at position 1: incomplete escape
    );
    try depTokenizer("\n\\",
        \\ERROR: illegal char '\' at position 1: incomplete escape
    );
    try depTokenizer("\r\\",
        \\ERROR: illegal char '\' at position 1: incomplete escape
    );
    try depTokenizer("\r\n\\",
        \\ERROR: illegal char '\' at position 2: incomplete escape
    );
    try depTokenizer(" \\",
        \\ERROR: illegal char '\' at position 1: incomplete escape
    );
}

test "error incomplete escape - dollar_sign" {
    try depTokenizer("$",
        \\ERROR: illegal char '$' at position 0: incomplete escape
    );
    try depTokenizer("\t$",
        \\ERROR: illegal char '$' at position 1: incomplete escape
    );
    try depTokenizer("\n$",
        \\ERROR: illegal char '$' at position 1: incomplete escape
    );
    try depTokenizer("\r$",
        \\ERROR: illegal char '$' at position 1: incomplete escape
    );
    try depTokenizer("\r\n$",
        \\ERROR: illegal char '$' at position 2: incomplete escape
    );
    try depTokenizer(" $",
        \\ERROR: illegal char '$' at position 1: incomplete escape
    );
}

test "error incomplete target" {
    try depTokenizer("foo.o",
        \\ERROR: incomplete target 'foo.o' at position 0
    );
    try depTokenizer("\tfoo.o",
        \\ERROR: incomplete target 'foo.o' at position 1
    );
    try depTokenizer("\nfoo.o",
        \\ERROR: incomplete target 'foo.o' at position 1
    );
    try depTokenizer("\rfoo.o",
        \\ERROR: incomplete target 'foo.o' at position 1
    );
    try depTokenizer("\r\nfoo.o",
        \\ERROR: incomplete target 'foo.o' at position 2
    );
    try depTokenizer(" foo.o",
        \\ERROR: incomplete target 'foo.o' at position 1
    );

    try depTokenizer("\\ foo.o",
        \\ERROR: incomplete target ' foo.o' at position 0
    );
    try depTokenizer("\\#foo.o",
        \\ERROR: incomplete target '#foo.o' at position 0
    );
    try depTokenizer("\\\\foo.o",
        \\ERROR: incomplete target '\foo.o' at position 0
    );
    try depTokenizer("$$foo.o",
        \\ERROR: incomplete target '$foo.o' at position 0
    );
}

test "error illegal char at position - bad target escape" {
    try depTokenizer("\\\t",
        \\ERROR: illegal char \x09 at position 1: bad target escape
    );
    try depTokenizer("\\\n",
        \\ERROR: illegal char \x0A at position 1: bad target escape
    );
    try depTokenizer("\\\r",
        \\ERROR: illegal char \x0D at position 1: bad target escape
    );
    try depTokenizer("\\\r\n",
        \\ERROR: illegal char \x0D at position 1: bad target escape
    );
}

test "error illegal char at position - expecting dollar_sign" {
    try depTokenizer("$\t",
        \\ERROR: illegal char \x09 at position 1: expecting '$'
    );
    try depTokenizer("$\n",
        \\ERROR: illegal char \x0A at position 1: expecting '$'
    );
    try depTokenizer("$\r",
        \\ERROR: illegal char \x0D at position 1: expecting '$'
    );
    try depTokenizer("$\r\n",
        \\ERROR: illegal char \x0D at position 1: expecting '$'
    );
}

test "error illegal char at position - invalid target" {
    try depTokenizer("foo\n.o",
        \\ERROR: illegal char \x0A at position 3: invalid target
    );
    try depTokenizer("foo\r.o",
        \\ERROR: illegal char \x0D at position 3: invalid target
    );
    try depTokenizer("foo\r\n.o",
        \\ERROR: illegal char \x0D at position 3: invalid target
    );
}

test "error target - continuation expecting end-of-line" {
    try depTokenizer("foo.o: \\\t",
        \\target = {foo.o}
        \\ERROR: illegal char \x09 at position 8: continuation expecting end-of-line
    );
    try depTokenizer("foo.o: \\ ",
        \\target = {foo.o}
        \\ERROR: illegal char ' ' at position 8: continuation expecting end-of-line
    );
    try depTokenizer("foo.o: \\x",
        \\target = {foo.o}
        \\ERROR: illegal char 'x' at position 8: continuation expecting end-of-line
    );
    try depTokenizer("foo.o: \\\x0dx",
        \\target = {foo.o}
        \\ERROR: illegal char 'x' at position 9: continuation expecting end-of-line
    );
}

test "error prereq - continuation expecting end-of-line" {
    try depTokenizer("foo.o: foo.h\\\x0dx",
        \\target = {foo.o}
        \\ERROR: illegal char 'x' at position 14: continuation expecting end-of-line
    );
}

test "error illegal char at position - expecting colon" {
    try depTokenizer("foo\t.o:",
        \\target = {foo}
        \\ERROR: illegal char '.' at position 4: expecting ':'
    );
    try depTokenizer("foo .o:",
        \\target = {foo}
        \\ERROR: illegal char '.' at position 4: expecting ':'
    );
    try depTokenizer("foo \n.o:",
        \\target = {foo}
        \\ERROR: illegal char \x0A at position 4: expecting ':'
    );
    try depTokenizer("foo.o\t\n:",
        \\target = {foo.o}
        \\ERROR: illegal char \x0A at position 6: expecting ':'
    );
}

// - tokenize input, emit textual representation, and compare to expect
fn depTokenizer(input: []const u8, expect: []const u8) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var it: Tokenizer = .{ .bytes = input };
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    var resolve_buf: std.ArrayListUnmanaged(u8) = .empty;
    var i: usize = 0;
    while (it.next()) |token| {
        if (i != 0) try buffer.appendSlice(arena, "\n");
        switch (token) {
            .target, .prereq => |bytes| {
                try buffer.appendSlice(arena, @tagName(token));
                try buffer.appendSlice(arena, " = {");
                for (bytes) |b| {
                    try buffer.append(arena, printable_char_tab[b]);
                }
                try buffer.appendSlice(arena, "}");
            },
            .target_must_resolve => {
                try buffer.appendSlice(arena, "target = {");
                try token.resolve(arena, &resolve_buf);
                for (resolve_buf.items) |b| {
                    try buffer.append(arena, printable_char_tab[b]);
                }
                resolve_buf.items.len = 0;
                try buffer.appendSlice(arena, "}");
            },
            .prereq_must_resolve => {
                try buffer.appendSlice(arena, "prereq = {");
                try token.resolve(arena, &resolve_buf);
                for (resolve_buf.items) |b| {
                    try buffer.append(arena, printable_char_tab[b]);
                }
                resolve_buf.items.len = 0;
                try buffer.appendSlice(arena, "}");
            },
            else => {
                try buffer.appendSlice(arena, "ERROR: ");
                try token.printError(arena, &buffer);
                break;
            },
        }
        i += 1;
    }

    if (std.mem.eql(u8, expect, buffer.items)) {
        try testing.expect(true);
        return;
    }

    try testing.expectEqualStrings(expect, buffer.items);
}

fn printCharValues(gpa: Allocator, list: *std.ArrayListUnmanaged(u8), bytes: []const u8) !void {
    for (bytes) |b| try list.append(gpa, printable_char_tab[b]);
}

fn printUnderstandableChar(gpa: Allocator, list: *std.ArrayListUnmanaged(u8), char: u8) !void {
    if (std.ascii.isPrint(char)) {
        try list.print(gpa, "'{c}'", .{char});
    } else {
        try list.print(gpa, "\\x{X:0>2}", .{char});
    }
}

// zig fmt: off
const printable_char_tab: [256]u8 = (
    "................................ !\"#$%&'()*+,-./0123456789:;<=>?" ++
    "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~." ++
    "................................................................" ++
    "................................................................"
).*;
