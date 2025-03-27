//! Central Processing Unit.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const apu = @import("apu.zig");
const gameboy = @import("gb.zig");
const memory = @import("memory.zig");
const ppu = @import("ppu.zig");
const timer = @import("timer.zig");

pub const CLOCK_RATE = 4194304;

/// Tracks the internal state of the cpu.
pub const State = struct {
    /// Interrupt Master Enable, enables the jump to the interrupt vectors,
    /// not whether interrupts are enabled or disabled.
    ime: bool,
    /// Whether the cpu is halted and waiting for an interrupt.
    halted: bool,
    /// The halt bug will cause the byte after halt to be read a second time.
    halt_bug: bool,
    /// State of the registers in the gameboy.
    registers: RegisterFile,
    /// How many cycles have passed since the last call to `cpu.step`.
    cycles_since_run: u8,

    pub fn init() @This() {
        return @This(){
            .ime = false,
            .halted = false,
            .halt_bug = false,
            .registers = .{ .named16 = .{ .af = 0, .bc = 0, .de = 0, .hl = 0, .sp = 0, .pc = 0 } },
            .cycles_since_run = 0,
        };
    }
};

/// Most registers can be accessed as one 16-bit register
/// or as two separate 8-bit registers so we use a C style union.
const RegisterFile = extern union {
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

    pub fn jsonStringify(
        self: @This(),
        writer: anytype,
    ) !void {
        try writer.beginObject();

        inline for (@typeInfo(@This()).@"union".fields) |unionField| {
            try writer.objectField(unionField.name);
            try writer.beginObject();

            inline for (@typeInfo(unionField.type).@"struct".fields) |field| {
                try writer.objectField(field.name);
                try writer.write(@field(@field(self, unionField.name), field.name));
            }

            try writer.endObject();
        }

        try writer.endObject();
    }
};

/// Contains information about the result of the most recent CPU
/// instruction that has affected flags.
pub const Flags = packed struct(u8) {
    _: u4 = 0,
    /// Carry flag.
    c: bool,
    /// Half Carry flag (BCD).
    h: bool,
    /// Subtraction flag (BCD).
    n: bool,
    /// Zero flag.
    z: bool,
};

/// Execute a single step of the cpu.
pub fn step(gb: *gameboy.State) u8 {
    const handled = handleInterrupt(gb);
    if (!handled) {
        fetchExecute(gb);
    }

    defer gb.cpu.cycles_since_run = 0;
    return gb.cpu.cycles_since_run;
}

/// Try to handle a single interrupt in priority order.
fn handleInterrupt(gb: *gameboy.State) bool {
    var handled = false;

    if (gb.memory.io.ie.v_blank and gb.memory.io.intf.v_blank) {
        gb.cpu.halted = false;
        if (gb.cpu.ime) {
            gb.memory.io.intf.v_blank = false;
            gb.cpu.ime = false;
            gb.tick();
            gb.tick();
            rst(gb, 0x40);
            handled = true;
        }
    } else if (gb.memory.io.ie.lcd and gb.memory.io.intf.lcd) {
        gb.cpu.halted = false;
        if (gb.cpu.ime) {
            gb.memory.io.intf.lcd = false;
            gb.cpu.ime = false;
            gb.tick();
            gb.tick();
            rst(gb, 0x48);
            handled = true;
        }
    } else if (gb.memory.io.ie.timer and gb.memory.io.intf.timer) {
        gb.cpu.halted = false;
        if (gb.cpu.ime) {
            gb.memory.io.intf.timer = false;
            gb.cpu.ime = false;
            gb.tick();
            gb.tick();
            rst(gb, 0x50);
            handled = true;
        }
    } else if (gb.memory.io.ie.serial and gb.memory.io.intf.serial) {
        gb.cpu.halted = false;
        if (gb.cpu.ime) {
            gb.memory.io.intf.serial = false;
            gb.cpu.ime = false;
            gb.tick();
            gb.tick();
            rst(gb, 0x58);
            handled = true;
        }
    } else if (gb.memory.io.ie.joypad and gb.memory.io.intf.joypad) {
        gb.cpu.halted = false;
        if (gb.cpu.ime) {
            gb.memory.io.intf.joypad = false;
            gb.cpu.ime = false;
            gb.tick();
            gb.tick();
            rst(gb, 0x60);
            handled = true;
        }
    }

    return handled;
}

/// Fetch, decode, and execute a single CPU instruction.
fn fetchExecute(gb: *gameboy.State) void {
    if (gb.cpu.halted) {
        gb.tick();
        return;
    }

    const op_code = fetch8(gb);
    if (gb.cpu.halt_bug) {
        @branchHint(.unlikely);
        gb.cpu.registers.named16.pc -%= 1;
        gb.cpu.halt_bug = false;
    }
    switch (op_code) {
        0x00 => nop(),
        0x01 => ld_rr_d16(gb, &gb.cpu.registers.named16.bc),
        0x02 => ld_drr_a(gb, &gb.cpu.registers.named16.bc),
        0x03 => inc_rr(gb, &gb.cpu.registers.named16.bc),
        0x04 => inc_r(gb, &gb.cpu.registers.named8.b),
        0x05 => dec_r(gb, &gb.cpu.registers.named8.b),
        0x06 => ld_r_d8(gb, &gb.cpu.registers.named8.b),
        0x07 => rlca(gb),
        0x08 => ld_da16_sp(gb),
        0x09 => add_hl_rr(gb, &gb.cpu.registers.named16.bc),
        0x0a => ld_a_drr(gb, &gb.cpu.registers.named16.bc),
        0x0b => dec_rr(gb, &gb.cpu.registers.named16.bc),
        0x0c => inc_r(gb, &gb.cpu.registers.named8.c),
        0x0d => dec_r(gb, &gb.cpu.registers.named8.c),
        0x0e => ld_r_d8(gb, &gb.cpu.registers.named8.c),
        0x0f => rrca(gb),

        0x10 => stop(gb),
        0x11 => ld_rr_d16(gb, &gb.cpu.registers.named16.de),
        0x12 => ld_drr_a(gb, &gb.cpu.registers.named16.de),
        0x13 => inc_rr(gb, &gb.cpu.registers.named16.de),
        0x14 => inc_r(gb, &gb.cpu.registers.named8.d),
        0x15 => dec_r(gb, &gb.cpu.registers.named8.d),
        0x16 => ld_r_d8(gb, &gb.cpu.registers.named8.d),
        0x17 => rla(gb),
        0x18 => jr_s8(gb),
        0x19 => add_hl_rr(gb, &gb.cpu.registers.named16.de),
        0x1a => ld_a_drr(gb, &gb.cpu.registers.named16.de),
        0x1b => dec_rr(gb, &gb.cpu.registers.named16.de),
        0x1c => inc_r(gb, &gb.cpu.registers.named8.e),
        0x1d => dec_r(gb, &gb.cpu.registers.named8.e),
        0x1e => ld_r_d8(gb, &gb.cpu.registers.named8.e),
        0x1f => rra(gb),

        0x20 => jr_cc_s8(gb, !gb.cpu.registers.named8.f.z),
        0x21 => ld_rr_d16(gb, &gb.cpu.registers.named16.hl),
        0x22 => ld_dhli_a(gb),
        0x23 => inc_rr(gb, &gb.cpu.registers.named16.hl),
        0x24 => inc_r(gb, &gb.cpu.registers.named8.h),
        0x25 => dec_r(gb, &gb.cpu.registers.named8.h),
        0x26 => ld_r_d8(gb, &gb.cpu.registers.named8.h),
        0x27 => daa(gb),
        0x28 => jr_cc_s8(gb, gb.cpu.registers.named8.f.z),
        0x29 => add_hl_rr(gb, &gb.cpu.registers.named16.hl),
        0x2a => ld_a_dhli(gb),
        0x2b => dec_rr(gb, &gb.cpu.registers.named16.hl),
        0x2c => inc_r(gb, &gb.cpu.registers.named8.l),
        0x2d => dec_r(gb, &gb.cpu.registers.named8.l),
        0x2e => ld_r_d8(gb, &gb.cpu.registers.named8.l),
        0x2f => cpl(gb),

        0x30 => jr_cc_s8(gb, !gb.cpu.registers.named8.f.c),
        0x31 => ld_rr_d16(gb, &gb.cpu.registers.named16.sp),
        0x32 => ld_dhld_a(gb),
        0x33 => inc_rr(gb, &gb.cpu.registers.named16.sp),
        0x34 => inc_dhl(gb),
        0x35 => dec_dhl(gb),
        0x36 => ld_dhl_d8(gb),
        0x37 => scf(gb),
        0x38 => jr_cc_s8(gb, gb.cpu.registers.named8.f.c),
        0x39 => add_hl_rr(gb, &gb.cpu.registers.named16.sp),
        0x3a => ld_a_dhld(gb),
        0x3b => dec_rr(gb, &gb.cpu.registers.named16.sp),
        0x3c => inc_r(gb, &gb.cpu.registers.named8.a),
        0x3d => dec_r(gb, &gb.cpu.registers.named8.a),
        0x3e => ld_r_d8(gb, &gb.cpu.registers.named8.a),
        0x3f => ccf(gb),

        0x40 => breakpoint(gb),
        0x41 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.c),
        0x42 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.d),
        0x43 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.e),
        0x44 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.h),
        0x45 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.l),
        0x46 => ld_r_dhl(gb, &gb.cpu.registers.named8.b),
        0x47 => ld_r_r(&gb.cpu.registers.named8.b, &gb.cpu.registers.named8.a),
        0x48 => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.b),
        0x49 => nop(),
        0x4a => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.d),
        0x4b => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.e),
        0x4c => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.h),
        0x4d => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.l),
        0x4e => ld_r_dhl(gb, &gb.cpu.registers.named8.c),
        0x4f => ld_r_r(&gb.cpu.registers.named8.c, &gb.cpu.registers.named8.a),

        0x50 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.b),
        0x51 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.c),
        0x52 => nop(),
        0x53 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.e),
        0x54 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.h),
        0x55 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.l),
        0x56 => ld_r_dhl(gb, &gb.cpu.registers.named8.d),
        0x57 => ld_r_r(&gb.cpu.registers.named8.d, &gb.cpu.registers.named8.a),
        0x58 => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.b),
        0x59 => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.c),
        0x5a => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.d),
        0x5b => nop(),
        0x5c => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.h),
        0x5d => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.l),
        0x5e => ld_r_dhl(gb, &gb.cpu.registers.named8.e),
        0x5f => ld_r_r(&gb.cpu.registers.named8.e, &gb.cpu.registers.named8.a),

        0x60 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.b),
        0x61 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.c),
        0x62 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.d),
        0x63 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.e),
        0x64 => nop(),
        0x65 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.l),
        0x66 => ld_r_dhl(gb, &gb.cpu.registers.named8.h),
        0x67 => ld_r_r(&gb.cpu.registers.named8.h, &gb.cpu.registers.named8.a),
        0x68 => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.b),
        0x69 => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.c),
        0x6a => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.d),
        0x6b => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.e),
        0x6c => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.h),
        0x6d => nop(),
        0x6e => ld_r_dhl(gb, &gb.cpu.registers.named8.l),
        0x6f => ld_r_r(&gb.cpu.registers.named8.l, &gb.cpu.registers.named8.a),

        0x70 => ld_dhl_r(gb, &gb.cpu.registers.named8.b),
        0x71 => ld_dhl_r(gb, &gb.cpu.registers.named8.c),
        0x72 => ld_dhl_r(gb, &gb.cpu.registers.named8.d),
        0x73 => ld_dhl_r(gb, &gb.cpu.registers.named8.e),
        0x74 => ld_dhl_r(gb, &gb.cpu.registers.named8.h),
        0x75 => ld_dhl_r(gb, &gb.cpu.registers.named8.l),
        0x76 => halt(gb),
        0x77 => ld_dhl_r(gb, &gb.cpu.registers.named8.a),
        0x78 => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.b),
        0x79 => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.c),
        0x7a => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.d),
        0x7b => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.e),
        0x7c => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.h),
        0x7d => ld_r_r(&gb.cpu.registers.named8.a, &gb.cpu.registers.named8.l),
        0x7e => ld_r_dhl(gb, &gb.cpu.registers.named8.a),
        0x7f => nop(),

        inline 0x80...0x87 => |op| add_a_r(gb, op),
        inline 0x88...0x8f => |op| adc_a_r(gb, op),

        inline 0x90...0x97 => |op| sub_a_r(gb, op),
        inline 0x98...0x9f => |op| sbc_a_r(gb, op),

        inline 0xa0...0xa7 => |op| and_a_r(gb, op),
        inline 0xa8...0xaf => |op| xor_a_r(gb, op),

        inline 0xb0...0xb7 => |op| or_a_r(gb, op),
        inline 0xb8...0xbf => |op| cp_a_r(gb, op),

        0xc0 => ret_cc(gb, !gb.cpu.registers.named8.f.z),
        0xc1 => pop_rr(gb, &gb.cpu.registers.named16.bc),
        0xc2 => jp_cc_a16(gb, !gb.cpu.registers.named8.f.z),
        0xc3 => jp_a16(gb),
        0xc4 => call_cc_a16(gb, !gb.cpu.registers.named8.f.z),
        0xc5 => push_rr(gb, &gb.cpu.registers.named16.bc),
        0xc6 => add_a_d8(gb),
        0xc7 => rst(gb, 0x00),
        0xc8 => ret_cc(gb, gb.cpu.registers.named8.f.z),
        0xc9 => ret(gb),
        0xca => jp_cc_a16(gb, gb.cpu.registers.named8.f.z),
        0xcb => cb_prefix(gb),
        0xcc => call_cc_a16(gb, gb.cpu.registers.named8.f.z),
        0xcd => call_a16(gb),
        0xce => adc_a_d8(gb),
        0xcf => rst(gb, 0x08),

        0xd0 => ret_cc(gb, !gb.cpu.registers.named8.f.c),
        0xd1 => pop_rr(gb, &gb.cpu.registers.named16.de),
        0xd2 => jp_cc_a16(gb, !gb.cpu.registers.named8.f.c),
        0xd3 => illegal(),
        0xd4 => call_cc_a16(gb, !gb.cpu.registers.named8.f.c),
        0xd5 => push_rr(gb, &gb.cpu.registers.named16.de),
        0xd6 => sub_a_d8(gb),
        0xd7 => rst(gb, 0x10),
        0xd8 => ret_cc(gb, gb.cpu.registers.named8.f.c),
        0xd9 => reti(gb),
        0xda => jp_cc_a16(gb, gb.cpu.registers.named8.f.c),
        0xdb => illegal(),
        0xdc => call_cc_a16(gb, gb.cpu.registers.named8.f.c),
        0xdd => illegal(),
        0xde => sbc_a_d8(gb),
        0xdf => rst(gb, 0x18),

        0xe0 => ld_da8_a(gb),
        0xe1 => pop_rr(gb, &gb.cpu.registers.named16.hl),
        0xe2 => ld_dc_a(gb),
        0xe3 => illegal(),
        0xe4 => illegal(),
        0xe5 => push_rr(gb, &gb.cpu.registers.named16.hl),
        0xe6 => and_a_d8(gb),
        0xe7 => rst(gb, 0x20),
        0xe8 => add_sp_s8(gb),
        0xe9 => jp_hl(gb),
        0xea => ld_da16_a(gb),
        0xeb => illegal(),
        0xec => illegal(),
        0xed => illegal(),
        0xee => xor_a_d8(gb),
        0xef => rst(gb, 0x28),

        0xf0 => ld_a_da8(gb),
        0xf1 => {
            pop_rr(gb, &gb.cpu.registers.named16.af);

            // don't set non-existent flags
            gb.cpu.registers.named8.f._ = 0;
        },
        0xf2 => ld_a_dc(gb),
        0xf3 => di(gb),
        0xf4 => illegal(),
        0xf5 => push_rr(gb, &gb.cpu.registers.named16.af),
        0xf6 => or_a_d8(gb),
        0xf7 => rst(gb, 0x30),
        0xf8 => ld_hl_sp_s8(gb),
        0xf9 => ld_sp_hl(gb),
        0xfa => ld_a_da16(gb),
        0xfb => ei(gb),
        0xfc => illegal(),
        0xfd => illegal(),
        0xfe => cp_a_d8(gb),
        0xff => rst(gb, 0x38),
    }
}

/// No-op, only advances the program counter.
fn nop() void {}

/// Load 2 bytes of immediate data into register pair `rr`.
fn ld_rr_d16(gb: *gameboy.State, rr: *u16) void {
    rr.* = fetch16(gb);
}

/// Store the contents of register A in the memory location specified
/// by register pair `rr`.
fn ld_drr_a(gb: *gameboy.State, rr: *const u16) void {
    cycleWrite(gb, rr.*, gb.cpu.registers.named8.a);
}

/// Increment the contents of register pair `rr` by 1.
fn inc_rr(gb: *gameboy.State, rr: *u16) void {
    gb.tick();
    rr.* +%= 1;
}

/// Increment the contents of register `r` by 1.
fn inc_r(gb: *gameboy.State, r: *u8) void {
    r.* +%= 1;

    gb.cpu.registers.named8.f.z = r.* == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = r.* & 0x0f == 0;
}

/// Decrement the contents of register `r` by 1.
fn dec_r(gb: *gameboy.State, r: *u8) void {
    r.* -%= 1;

    gb.cpu.registers.named8.f.z = r.* == 0;
    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = r.* & 0x0f == 0xf;
}

/// Load the 8-bit immediate operand `d8` into register `r`.
fn ld_r_d8(gb: *gameboy.State, r: *u8) void {
    r.* = fetch8(gb);
}

/// Rotate the contents of register `A` to the left.
fn rlca(gb: *gameboy.State) void {
    const bit7 = (gb.cpu.registers.named8.a & 0x80) != 0;

    gb.cpu.registers.named8.a = (gb.cpu.registers.named8.a << 1) | @intFromBool(bit7);

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit7;
}

/// Store the lower byte of stack pointer `SP` at the address
/// specified by the 16-bit immediate operand a16 and the upper
/// byte of SP at address a16 + 1.
fn ld_da16_sp(gb: *gameboy.State) void {
    const addr: memory.Addr = fetch16(gb);

    cycleWrite(gb, addr, @intCast(gb.cpu.registers.named16.sp & 0x00ff));
    cycleWrite(gb, addr + 1, @intCast(gb.cpu.registers.named16.sp >> 8));
}

/// Add the contents of register pair `rr` to the contents of
/// register pair `HL` and store the results in `HL`.
fn add_hl_rr(gb: *gameboy.State, rr: *const u16) void {
    gb.tick();

    const value, const overflowed = @addWithOverflow(gb.cpu.registers.named16.hl, rr.*);
    const half_carry = @addWithOverflow(
        @as(u12, @truncate(gb.cpu.registers.named16.hl)),
        @as(u12, @truncate(rr.*)),
    )[1] == 1;
    gb.cpu.registers.named16.hl = value;

    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = overflowed == 1;
}

/// Load the 8-bit contents of memory specified by register pair `rr`
/// into register `A`.
fn ld_a_drr(gb: *gameboy.State, rr: *const u16) void {
    gb.cpu.registers.named8.a = cycleRead(gb, rr.*);
}

/// Decrements the contenst of register pair `rr` by 1.
fn dec_rr(gb: *gameboy.State, rr: *u16) void {
    gb.tick();
    rr.* -%= 1;
}

/// Rotate the contents of register `A` to the right.
fn rrca(gb: *gameboy.State) void {
    const bit0 = (gb.cpu.registers.named8.a & 0x01) != 0;

    gb.cpu.registers.named8.a = @as(u8, @intFromBool(bit0)) << 7 | (gb.cpu.registers.named8.a >> 1);

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

fn stop(gb: *gameboy.State) void {
    _ = gb;
}

/// Rotate the contents of register `A` to the left,
/// through the carry flag.
fn rla(gb: *gameboy.State) void {
    const bit7 = (gb.cpu.registers.named8.a & 0x80) != 0;

    gb.cpu.registers.named8.a =
        (gb.cpu.registers.named8.a << 1) | @intFromBool(gb.cpu.registers.named8.f.c);

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit7;
}

/// Jump `s8` steps from the current address in the program counter.
fn jr_s8(gb: *gameboy.State) void {
    jr_cc_s8(gb, true);
}

/// Rotate the contents of register `A` to the right,
/// through the carry flag.
fn rra(gb: *gameboy.State) void {
    const bit0 = (gb.cpu.registers.named8.a & 0x01) != 0;

    gb.cpu.registers.named8.a =
        @as(u8, @intFromBool(gb.cpu.registers.named8.f.c)) << 7 | (gb.cpu.registers.named8.a >> 1);

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

/// Jump `s8` steps from the current address in the program counter
/// if the `condition` is true.
fn jr_cc_s8(gb: *gameboy.State, condition: bool) void {
    const offset: i8 = @bitCast(fetch8(gb));

    if (condition) {
        gb.tick();
        if (offset < 0) {
            gb.cpu.registers.named16.pc -%= @abs(offset);
        } else {
            gb.cpu.registers.named16.pc +%= @abs(offset);
        }
    }
}

/// Store the contents of register `A` into the memory location specified
/// by register pair `HL` and simultaneously increment `HL`.
fn ld_dhli_a(gb: *gameboy.State) void {
    ld_dhl_r(gb, &gb.cpu.registers.named8.a);
    gb.cpu.registers.named16.hl +%= 1;
}

/// Adjust register `A` to a binary-coded decimal number after BCD
/// addition and subtraction operations.
fn daa(gb: *gameboy.State) void {
    const value, const should_carry =
        if (gb.cpu.registers.named8.f.n) result: {
            var adjustment: u8 = 0;

            if (gb.cpu.registers.named8.f.h) {
                adjustment += 0x06;
            }
            if (gb.cpu.registers.named8.f.c) {
                adjustment += 0x60;
            }

            break :result .{ gb.cpu.registers.named8.a -% adjustment, 0 };
        } else result: {
            var adjustment: u8 = 0;

            if (gb.cpu.registers.named8.f.h or (gb.cpu.registers.named8.a & 0x0f) > 0x09) {
                adjustment += 0x06;
            }
            if (gb.cpu.registers.named8.f.c or gb.cpu.registers.named8.a > 0x99) {
                adjustment += 0x60;
            }

            break :result @addWithOverflow(gb.cpu.registers.named8.a, adjustment);
        };

    gb.cpu.registers.named8.a = value;
    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.h = false;
    // if subtraction wasn't performed and the unconverted value is greater than 0x99
    // or if the carry bit was already set, then our BCD value is also greater than 99
    gb.cpu.registers.named8.f.c = gb.cpu.registers.named8.f.c or should_carry == 1;
}

/// Load the contents of memory specified by register pair `HL` into
/// register `A` and simultaneously increment the contents of `HL`.
fn ld_a_dhli(gb: *gameboy.State) void {
    ld_r_dhl(gb, &gb.cpu.registers.named8.a);
    gb.cpu.registers.named16.hl +%= 1;
}

/// Take the one's complement of the contents of register `A`.
fn cpl(gb: *gameboy.State) void {
    gb.cpu.registers.named8.a = ~gb.cpu.registers.named8.a;

    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = true;
}

/// Store the contents of register `A` into the memmory location specified
/// by the register pair `HL` and simultaneously decrement `HL`.
fn ld_dhld_a(gb: *gameboy.State) void {
    ld_dhl_r(gb, &gb.cpu.registers.named8.a);
    gb.cpu.registers.named16.hl -%= 1;
}

/// Increment the contents of memory specified by register pair `HL` by 1.
fn inc_dhl(gb: *gameboy.State) void {
    const value = cycleRead(gb, gb.cpu.registers.named16.hl) +% 1;
    cycleWrite(gb, gb.cpu.registers.named16.hl, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = value & 0x0f == 0;
}

/// Decrement the contents of memory specified by register pair `HL` by 1.
fn dec_dhl(gb: *gameboy.State) void {
    const value = cycleRead(gb, gb.cpu.registers.named16.hl) -% 1;
    cycleWrite(gb, gb.cpu.registers.named16.hl, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = value & 0x0f == 0x0f;
}

/// Store the contents of 8-bit immediate operand d8 in the memory location
/// specified by register pair `HL`.
fn ld_dhl_d8(gb: *gameboy.State) void {
    const imm = fetch8(gb);
    cycleWrite(gb, gb.cpu.registers.named16.hl, imm);
}

/// Set the carry flag.
fn scf(gb: *gameboy.State) void {
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = true;
}

/// Load the contents of memory specified by register pair `HL` into register `A`
/// and simultaneously decrement `HL`.
fn ld_a_dhld(gb: *gameboy.State) void {
    ld_r_dhl(gb, &gb.cpu.registers.named8.a);
    gb.cpu.registers.named16.hl -%= 1;
}

/// Flip the carry flag.
fn ccf(gb: *gameboy.State) void {
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = !gb.cpu.registers.named8.f.c;
}

fn breakpoint(gb: *gameboy.State) void {
    _ = gb;
}

/// Load the contents of register `src` into register `dst`.
fn ld_r_r(dst: *u8, src: *const u8) void {
    dst.* = src.*;
}

/// Load the 8-bit contents of memory specified by register pair `HL` into
/// register `r`.
fn ld_r_dhl(gb: *gameboy.State, r: *u8) void {
    r.* = cycleRead(gb, gb.cpu.registers.named16.hl);
}

/// Store the contents of register `r` in the memory location specified
/// by register pair `HL`.
fn ld_dhl_r(gb: *gameboy.State, r: *const u8) void {
    cycleWrite(gb, gb.cpu.registers.named16.hl, r.*);
}

/// Pauses the cpu until an interrupt is pending.
fn halt(gb: *gameboy.State) void {
    gb.cpu.halted = true;

    // halt bug
    if (!gb.cpu.ime and
        ((gb.memory.io.ie.v_blank and gb.memory.io.intf.v_blank) or
            (gb.memory.io.ie.lcd and gb.memory.io.intf.lcd) or
            (gb.memory.io.ie.timer and gb.memory.io.intf.timer) or
            (gb.memory.io.ie.serial and gb.memory.io.intf.serial) or
            (gb.memory.io.ie.joypad and gb.memory.io.intf.joypad)))
    {
        gb.cpu.halt_bug = true;
    }
}

/// Add the contents of register `r` or the memory pointed to by `r` to the
/// contents of register `A` and store the results in register `A`.
fn add_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    add_a_x(gb, src);
}

/// Add the contents of register `r` or the memory pointed to by `r` and the
/// carry flag to the contents of register `A` and store the results in `A`.
fn adc_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    adc_a_x(gb, src);
}

/// Subtract the contents of register `r` or the memory pointed to by `r` from the
/// contents of register `A` and store the results in register `A`.
fn sub_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    sub_a_x(gb, src);
}

/// Subtract the contents of register `r` or the memory pointed to by `r` and the
/// carry flag from the contents of register `A`, and store the results in `A`.
fn sbc_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    sbc_a_x(gb, src);
}

/// Take the bitwise AND of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn and_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    and_a_x(gb, src);
}

/// Take the bitwise XOR of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn xor_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    xor_a_x(gb, src);
}

/// Take the bitwise OR of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn or_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    or_a_x(gb, src);
}

/// Compare the contents of register `r` or the memory pointed to by `r` and
/// the contents of register `A` by calculating `A - B`, and set the `Z` flag
/// if they are equal.
fn cp_a_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    cp_a_x(gb, src);
}

/// If the `condition` is true, control is returned to the source program by
/// popping from the memory stack the program counter value that was pushed
/// to the stack when the subroutine was called.
fn ret_cc(gb: *gameboy.State, condition: bool) void {
    gb.tick();

    if (condition) {
        ret(gb);
    }
}

/// Pop the contents from the memory stack into register pair `rr`.
fn pop_rr(gb: *gameboy.State, rr: *u16) void {
    const lo = cycleRead(gb, gb.cpu.registers.named16.sp);
    gb.cpu.registers.named16.sp +%= 1;
    const hi = cycleRead(gb, gb.cpu.registers.named16.sp);
    gb.cpu.registers.named16.sp +%= 1;

    rr.* = @as(u16, hi) << 8 | lo;
}

/// Load the 16-bit immediate operand `a16` into the program counter if
/// the `condition` is true. If the `condition` is true, then the subsequent
/// instruction starts at address `a16`. If not, the contents of `PC` are
/// incremented, and the next instruction following the current JP instruction
/// is executed (as usual).
fn jp_cc_a16(gb: *gameboy.State, condition: bool) void {
    const addr: memory.Addr = fetch16(gb);

    if (condition) {
        gb.tick();
        gb.cpu.registers.named16.pc = addr;
    }
}

/// Load the 16-bit immediate operand `a16` into the program counter.
/// `a16` specifies the address of the subsequently executed instruction.
fn jp_a16(gb: *gameboy.State) void {
    jp_cc_a16(gb, true);
}

/// If the `condition` is true, the program counter value corresponding to the
/// memory location of the instruction following the CALL instruction is pushed
/// to the 2 bytes following the memory byte specified by the stack pointer. The
/// 16-bit immediate operand `a16` is then loaded into PC.
fn call_cc_a16(gb: *gameboy.State, condition: bool) void {
    const addr: memory.Addr = fetch16(gb);

    if (condition) {
        push_rr(gb, &gb.cpu.registers.named16.pc);
        gb.cpu.registers.named16.pc = addr;
    }
}

/// Push the contents of register pair `rr` onto the memory stack.
fn push_rr(gb: *gameboy.State, rr: *const u16) void {
    gb.tick();

    gb.cpu.registers.named16.sp -%= 1;
    cycleWrite(gb, gb.cpu.registers.named16.sp, @intCast(rr.* >> 8));
    gb.cpu.registers.named16.sp -%= 1;
    cycleWrite(gb, gb.cpu.registers.named16.sp, @intCast(rr.* & 0x00ff));
}

/// Add the contents of the 8-bit immediate operand `d8` to the contents of register `A`,
/// and store the results in `A`.
fn add_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    add_a_x(gb, src);
}

/// Push the current value of the program counter onto the memory stack, and
/// load `addr` into `PC` memory addresses.
pub fn rst(gb: *gameboy.State, comptime addr: memory.Addr) void {
    push_rr(gb, &gb.cpu.registers.named16.pc);
    gb.cpu.registers.named16.pc = addr;
}

/// Pop from the memory stack the program counter value pushed when the
/// subroutine was called, returning control to the source program.
fn ret(gb: *gameboy.State) void {
    gb.tick();
    pop_rr(gb, &gb.cpu.registers.named16.pc);
}

/// In memory, push the program counter value corresponding to the address following
/// the CALL instruction to the 2 bytes following the byte specified by the current
/// stack pointer. Then load the 16-bit immediate operand `a16` into `PC`.
///
/// The subroutine is placed after the location specified by the new PC value. When
/// the subroutine finishes, control is returned to the source program using a return
/// instruction and by popping the starting address of the next instruction (which
/// was just pushed) and moving it to the `PC`.
///
/// With the push, the current value of `SP` is decremented by 1, and the higher-order
/// byte of `PC` is loaded in the memory address specified by the new `SP` value. The
/// value of `SP` is then decremented by 1 again, and the lower-order byte of `PC` is
/// loaded in the memory address specified by that value of `SP`.
fn call_a16(gb: *gameboy.State) void {
    call_cc_a16(gb, true);
}

/// Add the contents of the 8-bit immediate operand `d8` and the `CY` flag to the
/// contents of register `A`, and store the results in `A`.
fn adc_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    adc_a_x(gb, src);
}

/// Subtract the contents of the 8-bit immediate operand `d8` from the contents of
/// register `A`, and store the results in `A`.
fn sub_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    sub_a_x(gb, src);
}

/// Used when an interrupt-service routine finishes. The address for the return
/// from the interrupt is loaded in the program counter `PC`. The master interrupt
/// enable flag is returned to its pre-interrupt status.
fn reti(gb: *gameboy.State) void {
    ret(gb);
    gb.cpu.ime = true;
}

/// Subtract the contents of the 8-bit immediate operand `d8` and the carry flag
/// from the contents of register `A`, and store the results in `A`.
fn sbc_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    sbc_a_x(gb, src);
}

/// Store the contents of register `A` in the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by the 8-bit
/// immediate operand a8.
fn ld_da8_a(gb: *gameboy.State) void {
    const imm = fetch8(gb);
    cycleWrite(gb, @as(u16, 0xff00) + imm, gb.cpu.registers.named8.a);
}

/// Store the contents of register `A` in the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by register `C`.
fn ld_dc_a(gb: *gameboy.State) void {
    cycleWrite(gb, @as(u16, 0xff00) + gb.cpu.registers.named8.c, gb.cpu.registers.named8.a);
}

/// Take bitwise AND of the contents of 8-bit immediate operand `d8` and the contents
/// of register `A`, and store the results in `A`.
fn and_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    and_a_x(gb, src);
}

/// Add the contents of the 8-bit signed immediate operand `s8` and the stack pointer,
/// and store the results in `SP`.
fn add_sp_s8(gb: *gameboy.State) void {
    gb.tick();
    gb.tick();

    const offset: i8 = @bitCast(fetch8(gb));
    const value = if (offset < 0) result: {
        break :result gb.cpu.registers.named16.sp -% @abs(offset);
    } else result: {
        break :result gb.cpu.registers.named16.sp +% @abs(offset);
    };
    const half_carry = @addWithOverflow(
        @as(u4, @truncate(gb.cpu.registers.named16.sp)),
        @as(u4, @truncate(@as(u8, @bitCast(offset)))),
    )[1] == 1;
    const carry = @addWithOverflow(
        @as(u8, @truncate(gb.cpu.registers.named16.sp)),
        @as(u8, @bitCast(offset)),
    )[1] == 1;
    gb.cpu.registers.named16.sp = value;

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = carry;
}

/// Load the contents of register pair `HL` into the program counter. The next instruction
/// is fetched from the location specified by the new value of `PC`.
fn jp_hl(gb: *gameboy.State) void {
    gb.cpu.registers.named16.pc = gb.cpu.registers.named16.hl;
}

/// Add the 8-bit signed operand `s8` (values -128 to +127) to the stack pointer `SP`,
/// and store the result in register pair `HL`.
fn ld_hl_sp_s8(gb: *gameboy.State) void {
    gb.tick();

    const offset: i8 = @bitCast(fetch8(gb));
    const value = if (offset < 0) result: {
        break :result gb.cpu.registers.named16.sp -% @abs(offset);
    } else result: {
        break :result gb.cpu.registers.named16.sp +% @abs(offset);
    };
    const half_carry = @addWithOverflow(
        @as(u4, @truncate(gb.cpu.registers.named16.sp)),
        @as(u4, @truncate(@as(u8, @bitCast(offset)))),
    )[1] == 1;
    const carry = @addWithOverflow(
        @as(u8, @truncate(gb.cpu.registers.named16.sp)),
        @as(u8, @bitCast(offset)),
    )[1] == 1;
    gb.cpu.registers.named16.hl = value;

    gb.cpu.registers.named8.f.z = false;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = carry;
}

/// Load the contents of register pair `HL` into the stack pointer `SP`.
fn ld_sp_hl(gb: *gameboy.State) void {
    gb.tick();
    gb.cpu.registers.named16.sp = gb.cpu.registers.named16.hl;
}

/// Store the contents of register `A` in the internal RAM or register specified by
/// the 16-bit immediate operand `a16`.
fn ld_da16_a(gb: *gameboy.State) void {
    const addr: memory.Addr = fetch16(gb);
    cycleWrite(gb, addr, gb.cpu.registers.named8.a);
}

/// Take the bitwise XOR of the contents of the 8-bit immediate operand `d8` and
/// the contents of register `A`, and store the results in register `A`.
fn xor_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    xor_a_x(gb, src);
}

/// Load into register `A` the contents of the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by the 8-bit
/// immediate operand `a8`.
fn ld_a_da8(gb: *gameboy.State) void {
    const imm = fetch8(gb);
    gb.cpu.registers.named8.a = cycleRead(gb, @as(u16, 0xff00) + imm);
}

/// Load into register `A` the contents of the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by register `C`.
fn ld_a_dc(gb: *gameboy.State) void {
    gb.cpu.registers.named8.a = cycleRead(gb, @as(u16, 0xff00) + gb.cpu.registers.named8.c);
}

/// Reset the interrupt master enable flag and prohibit maskable interrupts.
fn di(gb: *gameboy.State) void {
    gb.cpu.ime = false;
}

/// Take the bitwise OR of the contents of the 8-bit immediate operand `d8` and
/// the contents of register `A`, and store the results in `A`.
fn or_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    or_a_x(gb, src);
}

/// Load into register `A` the contents of the internal RAM or register specified
/// by the 16-bit immediate operand `a16`.
fn ld_a_da16(gb: *gameboy.State) void {
    const addr: memory.Addr = fetch16(gb);
    gb.cpu.registers.named8.a = cycleRead(gb, addr);
}

/// Set the interrupt master enable flag and enable maskable interrupts. This
/// instruction can be used in an interrupt routine to enable higher-order interrupts.
fn ei(gb: *gameboy.State) void {
    gb.cpu.ime = true;
}

/// Compare the contents of register `A` and the contents of the 8-bit immediate
/// operand `d8` by calculating `A - d8`, and set the `Z` flag if they are equal.
fn cp_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    cp_a_x(gb, src);
}

/// 16-bit opcodes where the first 8 bits are 0xcb.
fn cb_prefix(gb: *gameboy.State) void {
    const op_code = fetch8(gb);
    switch (op_code) {
        inline 0x00...0x07 => |op| rlc_r(gb, op),
        inline 0x08...0x0f => |op| rrc_r(gb, op),

        inline 0x10...0x17 => |op| rl_r(gb, op),
        inline 0x18...0x1f => |op| rr_r(gb, op),

        inline 0x20...0x27 => |op| sla_r(gb, op),
        inline 0x28...0x2f => |op| sra_r(gb, op),

        inline 0x30...0x37 => |op| swap_r(gb, op),
        inline 0x38...0x3f => |op| srl_r(gb, op),

        inline 0x40...0x7f => |op| bit_x_r(gb, op),
        inline 0x80...0xbf => |op| res_x_r(gb, op),
        inline 0xc0...0xff => |op| set_x_r(gb, op),
    }
}

/// Rotate the contents of register `r` to the left.
fn rlc_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit7 = (src & 0x80) != 0;

    const value = (src << 1) | @intFromBool(bit7);
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit7;
}

/// Rotate the contents of register `r` to the right.
fn rrc_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit0 = (src & 0x01) != 0;

    const value = @as(u8, @intFromBool(bit0)) << 7 | (src >> 1);
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

/// Rotate the contents of register `r` to the left,
/// through the carry flag.
fn rl_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit7 = (src & 0x80) != 0;

    const value = (src << 1) | @intFromBool(gb.cpu.registers.named8.f.c);
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit7;
}

/// Rotate the contents of register `r` to the right,
/// through the carry flag.
fn rr_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit0 = (src & 0x01) != 0;

    const value =
        @as(u8, @intFromBool(gb.cpu.registers.named8.f.c)) << 7 | (src >> 1);
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

/// Shift the contents of register `r` to the left.
fn sla_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit7 = (src & 0x80) != 0;

    const value = src << 1;
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit7;
}

/// Shift the contents of register `r` to the right, preserving bit 7.
fn sra_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit7 = src & 0x80;
    const bit0 = (src & 0x01) != 0;

    const value = bit7 | (src >> 1);
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

/// Swap the lower and higher four bits of register `r`.
fn swap_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const value = (src & 0x0f) << 4 | (src & 0xf0) >> 4;
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = false;
}

/// Shift the contents of register `r` to the right, resetting bit 7.
fn srl_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const bit0 = (src & 0x01) != 0;

    const value = src >> 1;
    setDst(gb, op_code, value);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = bit0;
}

/// Copy the complement of the contents of bit `x` in register `r` to the `Z` flag of
/// the program status word.
fn bit_x_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const x = @as(u3, @truncate(op_code >> 3));
    const bx = src & (1 << x) != 0;

    gb.cpu.registers.named8.f.z = !bx;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = true;
}

/// Reset bit `x` in register `r` to 0.
fn res_x_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const x = @as(u3, @truncate(op_code >> 3));

    setDst(gb, op_code, src & ~(@as(u8, 1 << x)));
}

/// Set bit `x` in register `r` to 1.
fn set_x_r(gb: *gameboy.State, op_code: comptime_int) void {
    const src = getSrc(gb, op_code);
    const x = @as(u3, @truncate(op_code >> 3));

    setDst(gb, op_code, src | (1 << x));
}

fn illegal() void {
    // TODO: handle
}

fn add_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @addWithOverflow(gb.cpu.registers.named8.a, src);
    const half_carry = @addWithOverflow(
        @as(u4, @truncate(gb.cpu.registers.named8.a)),
        @as(u4, @truncate(src)),
    )[1] == 1;
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = overflowed == 1;
}

fn adc_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflow = addManyWithOverflow(u8, 3, [_]u8{
        gb.cpu.registers.named8.a,
        src,
        @intFromBool(gb.cpu.registers.named8.f.c),
    });
    const half_carry = addManyWithOverflow(u4, 3, [_]u4{
        @as(u4, @truncate(gb.cpu.registers.named8.a)),
        @as(u4, @truncate(src)),
        @intFromBool(gb.cpu.registers.named8.f.c),
    })[1];
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = overflow;
}

fn sub_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @subWithOverflow(gb.cpu.registers.named8.a, src);
    const half_carry = @subWithOverflow(
        @as(u4, @truncate(gb.cpu.registers.named8.a)),
        @as(u4, @truncate(src)),
    )[1] == 1;
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = overflowed == 1;
}

fn sbc_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = subManyWithOverflow(u8, 3, [_]u8{
        gb.cpu.registers.named8.a,
        src,
        @intFromBool(gb.cpu.registers.named8.f.c),
    });
    const half_carry = subManyWithOverflow(u4, 3, [_]u4{
        @as(u4, @truncate(gb.cpu.registers.named8.a)),
        @as(u4, @truncate(src)),
        @intFromBool(gb.cpu.registers.named8.f.c),
    })[1];
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = half_carry;
    gb.cpu.registers.named8.f.c = overflowed;
}

fn and_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.cpu.registers.named8.a & src;
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = true;
    gb.cpu.registers.named8.f.c = false;
}

fn xor_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.cpu.registers.named8.a ^ src;
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = false;
}

fn or_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.cpu.registers.named8.a | src;
    gb.cpu.registers.named8.a = value;

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = false;
    gb.cpu.registers.named8.f.h = false;
    gb.cpu.registers.named8.f.c = false;
}

fn cp_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @subWithOverflow(gb.cpu.registers.named8.a, src);

    gb.cpu.registers.named8.f.z = value == 0;
    gb.cpu.registers.named8.f.n = true;
    gb.cpu.registers.named8.f.h = @subWithOverflow(
        @as(u4, @truncate(gb.cpu.registers.named8.a)),
        @as(u4, @truncate(src)),
    )[1] == 1;
    gb.cpu.registers.named8.f.c = overflowed == 1;
}

/// Fetches 16 bits from the memory pointed to by `PC`, incrementing `PC` twice.
fn fetch16(gb: *gameboy.State) u16 {
    const lo = fetch8(gb);
    const hi = fetch8(gb);

    return @as(u16, hi) << 8 | lo;
}

/// Fetches 8 bits from the memory pointed to by `PC` and incrementing `PC`.
fn fetch8(gb: *gameboy.State) u8 {
    const value = cycleRead(gb, gb.cpu.registers.named16.pc);
    gb.cpu.registers.named16.pc +%= 1;

    return value;
}

fn cycleRead(gb: *gameboy.State, addr: memory.Addr) u8 {
    gb.tick();
    return memory.readByte(gb, addr);
}

fn cycleWrite(gb: *gameboy.State, addr: memory.Addr, value: u8) void {
    gb.tick();
    memory.writeByte(gb, addr, value);
}

/// Like `@addWithOverflow` but for an arbitary number of arguments.
fn addManyWithOverflow(comptime T: type, n: comptime_int, args: [n]T) struct { T, bool } {
    var result: T = 0;
    var overflowed: bool = false;

    for (args) |arg| {
        result, const did_overflow = @addWithOverflow(result, arg);
        overflowed = overflowed or did_overflow == 1;
    }

    return .{ result, overflowed };
}

/// Like `@subWithOverflow` but for an arbitary number of arguments.
/// Note that unlike `addManyWithOverflow`, order is important so
/// `[_]u8{ a, b, c }` will become `a - b - c`.
fn subManyWithOverflow(comptime T: type, n: comptime_int, args: [n]T) struct { T, bool } {
    var result: T = args[0];
    var overflowed: bool = false;

    for (args[1..]) |arg| {
        result, const did_overflow = @subWithOverflow(result, arg);
        overflowed = overflowed or did_overflow == 1;
    }

    return .{ result, overflowed };
}

/// Either reads from the register `r` if it is an 8-bit register or
/// reads from the memory pointed to by `rr` if it is a 16-bit register,
/// deciding based on the `op_code`.
fn getSrc(gb: *gameboy.State, op_code: comptime_int) u8 {
    return switch (@as(u3, @truncate(op_code))) {
        0 => gb.cpu.registers.named8.b,
        1 => gb.cpu.registers.named8.c,
        2 => gb.cpu.registers.named8.d,
        3 => gb.cpu.registers.named8.e,
        4 => gb.cpu.registers.named8.h,
        5 => gb.cpu.registers.named8.l,
        6 => cycleRead(gb, gb.cpu.registers.named16.hl),
        7 => gb.cpu.registers.named8.a,
    };
}

/// Either writes to the register `r` if it is an 8-bit register or
/// writes to the memory pointed to by `rr` if it is a 16-bit register,
/// deciding based on the `op_code`.
fn setDst(gb: *gameboy.State, op_code: comptime_int, value: u8) void {
    switch (@as(u3, @truncate(op_code))) {
        0 => gb.cpu.registers.named8.b = value,
        1 => gb.cpu.registers.named8.c = value,
        2 => gb.cpu.registers.named8.d = value,
        3 => gb.cpu.registers.named8.e = value,
        4 => gb.cpu.registers.named8.h = value,
        5 => gb.cpu.registers.named8.l = value,
        6 => cycleWrite(gb, gb.cpu.registers.named16.hl, value),
        7 => gb.cpu.registers.named8.a = value,
    }
}

test "RegisterFile get" {
    const registers = RegisterFile{ .named16 = .{ .af = 0x1234, .bc = 0, .de = 0, .hl = 0xbeef, .sp = 0, .pc = 0 } };

    try testing.expectEqual(0x12, registers.named8.a);
    try testing.expectEqual(0xef, registers.named8.l);
}

test "RegisterFile set" {
    var registers = RegisterFile{ .named16 = .{ .af = 0, .bc = 0, .de = 0xfeed, .hl = 0, .sp = 0, .pc = 0 } };

    registers.named8.d = 0xaa;
    try testing.expectEqual(0xaa, registers.named8.d);
    try testing.expectEqual(0xaaed, registers.named16.de);

    registers.named8.e = 0xbb;
    try testing.expectEqual(0xaabb, registers.named16.de);
}
