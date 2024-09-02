export fn entry() callconv(.Interrupt) void {}

// error
// backend=stage2
// target=aarch64-linux-none
//
// :1:29: error: callconv 'Interrupt' is only available on AVR, CSKY, M68k, MIPS, MSP430, RISC-V, and x86, not aarch64
