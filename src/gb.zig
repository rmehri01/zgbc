const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

pub const Addr = u16;

/// The main state of the gameboy emulator.
pub const State = struct {
    registers: RegisterFile,

    pub fn tick(self: *@This()) void {
        _ = self; // autofix
    }
};

/// Most registers can be accessed as one 16-bit register
/// or as two separate 8-bit registers so we use a C style union.
const RegisterFile = extern union {
    arr16: [6]u16,
    arr8: [8]u8,
    named16: extern struct {
        af: u16,
        bc: u16,
        de: u16,
        hl: u16,
        sp: u16,
        pc: u16,
    },
    named8: extern struct {
        f: Flags,
        a: u8,
        c: u8,
        b: u8,
        e: u8,
        d: u8,
        l: u8,
        h: u8,
    },

    comptime {
        assert(@sizeOf(@This()) == 6 * @sizeOf(u16));
    }
};

/// Contains information about the result of the most recent
/// instruction that has affected flags.
const Flags = packed struct(u8) {
    /// Zero flag.
    z: bool,
    /// Subtraction flag (BCD).
    n: bool,
    /// Half Carry flag (BCD).
    h: bool,
    /// Carry flag.
    c: bool,
    _: u4,
};

test "RegisterFile get" {
    const registers = RegisterFile{ .arr16 = [6]u16{ 0x1234, 0, 0, 0xbeef, 0, 0 } };

    try testing.expectEqual(0x1234, registers.named16.af);
    try testing.expectEqual(0xbeef, registers.named16.hl);
    try testing.expectEqual(0x12, registers.named8.a);
    try testing.expectEqual(0xef, registers.named8.l);
}

test "RegisterFile set" {
    var registers = RegisterFile{ .arr16 = [6]u16{ 0, 0, 0xfeed, 0, 0, 0 } };

    try testing.expectEqual(0xfeed, registers.named16.de);
    registers.named16.de = 0xdeef;
    try testing.expectEqual(0xdeef, registers.named16.de);

    registers.named8.d = 0xaa;
    try testing.expectEqual(0xaa, registers.named8.d);
    try testing.expectEqual(0xaaef, registers.named16.de);

    registers.named8.e = 0xbb;
    try testing.expectEqual(0xaabb, registers.named16.de);
}
