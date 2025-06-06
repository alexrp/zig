inline fn foo(x: i32) i32 {
    if (x <= 0) {
        return 0;
    } else {
        return x * 2 + foo(x - 1);
    }
}

pub export fn entry() void {
    var x: i32 = 4;
    _ = &x;
    _ = foo(x) == 20;
}

inline fn first() void {
    second();
}

inline fn second() void {
    third();
}

inline fn third() void {
    first();
}

pub export fn entry2() void {
    first();
}

// error
//
// :5:27: error: inline call is recursive
// :12:12: note: called inline here
// :24:10: error: inline call is recursive
// :20:10: note: called inline here
// :16:11: note: called inline here
// :28:10: note: called inline here
