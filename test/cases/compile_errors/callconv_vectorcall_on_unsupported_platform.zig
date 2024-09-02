export fn entry() callconv(.Vectorcall) void {}

// error
// backend=stage2
// target=arm-linux-none
//
// :1:29: error: callconv 'Vectorcall' is only available on AArch64, RISC-V, and x86, not arm
