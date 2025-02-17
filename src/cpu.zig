const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// Executes a single CPU instruction.
pub fn exec(gb: *gameboy.State) void {
    // If the scheduled `ei` instruction wasn't cancelled, then enable
    // interrupts after the next instruction runs.
    const scheduled_ei = gb.scheduled_ei;
    defer if (scheduled_ei and gb.scheduled_ei) {
        @branchHint(.unlikely);
        gb.ime = true;
    };

    const op_code = fetch8(gb);
    switch (op_code) {
        0x00 => nop(),
        0x01 => ld_rr_d16(gb, &gb.registers.named16.bc),
        0x02 => ld_drr_a(gb, &gb.registers.named16.bc),
        0x03 => inc_rr(gb, &gb.registers.named16.bc),
        0x04 => inc_r(gb, &gb.registers.named8.b),
        0x05 => dec_r(gb, &gb.registers.named8.b),
        0x06 => ld_r_d8(gb, &gb.registers.named8.b),
        0x07 => rlca(gb),
        0x08 => ld_da16_sp(gb),
        0x09 => add_hl_rr(gb, &gb.registers.named16.bc),
        0x0a => ld_a_drr(gb, &gb.registers.named16.bc),
        0x0b => dec_rr(gb, &gb.registers.named16.bc),
        0x0c => inc_r(gb, &gb.registers.named8.c),
        0x0d => dec_r(gb, &gb.registers.named8.c),
        0x0e => ld_r_d8(gb, &gb.registers.named8.c),
        0x0f => rrca(gb),

        0x10 => stop(gb),
        0x11 => ld_rr_d16(gb, &gb.registers.named16.de),
        0x12 => ld_drr_a(gb, &gb.registers.named16.de),
        0x13 => inc_rr(gb, &gb.registers.named16.de),
        0x14 => inc_r(gb, &gb.registers.named8.d),
        0x15 => dec_r(gb, &gb.registers.named8.d),
        0x16 => ld_r_d8(gb, &gb.registers.named8.d),
        0x17 => rla(gb),
        0x18 => jr_s8(gb),
        0x19 => add_hl_rr(gb, &gb.registers.named16.de),
        0x1a => ld_a_drr(gb, &gb.registers.named16.de),
        0x1b => dec_rr(gb, &gb.registers.named16.de),
        0x1c => inc_r(gb, &gb.registers.named8.e),
        0x1d => dec_r(gb, &gb.registers.named8.e),
        0x1e => ld_r_d8(gb, &gb.registers.named8.e),
        0x1f => rra(gb),

        0x20 => jr_cc_s8(gb, !gb.registers.named8.f.z),
        0x21 => ld_rr_d16(gb, &gb.registers.named16.hl),
        0x22 => ld_dhl_inc_a(gb),
        0x23 => inc_rr(gb, &gb.registers.named16.hl),
        0x24 => inc_r(gb, &gb.registers.named8.h),
        0x25 => dec_r(gb, &gb.registers.named8.h),
        0x26 => ld_r_d8(gb, &gb.registers.named8.h),
        0x27 => daa(gb),
        0x28 => jr_cc_s8(gb, gb.registers.named8.f.z),
        0x29 => add_hl_rr(gb, &gb.registers.named16.hl),
        0x2a => ld_a_dhl_inc(gb),
        0x2b => dec_rr(gb, &gb.registers.named16.hl),
        0x2c => inc_r(gb, &gb.registers.named8.l),
        0x2d => dec_r(gb, &gb.registers.named8.l),
        0x2e => ld_r_d8(gb, &gb.registers.named8.l),
        0x2f => cpl(gb),

        0x30 => jr_cc_s8(gb, !gb.registers.named8.f.c),
        0x31 => ld_rr_d16(gb, &gb.registers.named16.sp),
        0x32 => ld_dhl_dec_a(gb),
        0x33 => inc_rr(gb, &gb.registers.named16.sp),
        0x34 => inc_dhl(gb),
        0x35 => dec_dhl(gb),
        0x36 => ld_dhl_d8(gb),
        0x37 => scf(gb),
        0x38 => jr_cc_s8(gb, gb.registers.named8.f.c),
        0x39 => add_hl_rr(gb, &gb.registers.named16.sp),
        0x3a => ld_a_dhl_dec(gb),
        0x3b => dec_rr(gb, &gb.registers.named16.sp),
        0x3c => inc_r(gb, &gb.registers.named8.a),
        0x3d => dec_r(gb, &gb.registers.named8.a),
        0x3e => ld_r_d8(gb, &gb.registers.named8.a),
        0x3f => ccf(gb),

        0x40 => breakpoint(gb),
        0x41 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.c),
        0x42 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.d),
        0x43 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.e),
        0x44 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.h),
        0x45 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.l),
        0x46 => ld_r_dhl(gb, &gb.registers.named8.b),
        0x47 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.a),
        0x48 => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.b),
        0x49 => nop(),
        0x4a => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.d),
        0x4b => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.e),
        0x4c => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.h),
        0x4d => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.l),
        0x4e => ld_r_dhl(gb, &gb.registers.named8.c),
        0x4f => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.a),

        0x50 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.b),
        0x51 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.c),
        0x52 => nop(),
        0x53 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.e),
        0x54 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.h),
        0x55 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.l),
        0x56 => ld_r_dhl(gb, &gb.registers.named8.d),
        0x57 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.a),
        0x58 => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.b),
        0x59 => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.c),
        0x5a => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.d),
        0x5b => nop(),
        0x5c => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.h),
        0x5d => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.l),
        0x5e => ld_r_dhl(gb, &gb.registers.named8.e),
        0x5f => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.a),

        0x60 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.b),
        0x61 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.c),
        0x62 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.d),
        0x63 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.e),
        0x64 => nop(),
        0x65 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.l),
        0x66 => ld_r_dhl(gb, &gb.registers.named8.h),
        0x67 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.a),
        0x68 => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.b),
        0x69 => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.c),
        0x6a => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.d),
        0x6b => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.e),
        0x6c => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.h),
        0x6d => nop(),
        0x6e => ld_r_dhl(gb, &gb.registers.named8.l),
        0x6f => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.a),

        0x70 => ld_dhl_r(gb, &gb.registers.named8.b),
        0x71 => ld_dhl_r(gb, &gb.registers.named8.c),
        0x72 => ld_dhl_r(gb, &gb.registers.named8.d),
        0x73 => ld_dhl_r(gb, &gb.registers.named8.e),
        0x74 => ld_dhl_r(gb, &gb.registers.named8.h),
        0x75 => ld_dhl_r(gb, &gb.registers.named8.l),
        0x76 => halt(gb),
        0x77 => ld_dhl_r(gb, &gb.registers.named8.a),
        0x78 => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.b),
        0x79 => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.c),
        0x7a => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.d),
        0x7b => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.e),
        0x7c => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.h),
        0x7d => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.l),
        0x7e => ld_r_dhl(gb, &gb.registers.named8.a),
        0x7f => nop(),

        0x80 => add_a_r(u8, gb, &gb.registers.named8.b),
        0x81 => add_a_r(u8, gb, &gb.registers.named8.c),
        0x82 => add_a_r(u8, gb, &gb.registers.named8.d),
        0x83 => add_a_r(u8, gb, &gb.registers.named8.e),
        0x84 => add_a_r(u8, gb, &gb.registers.named8.h),
        0x85 => add_a_r(u8, gb, &gb.registers.named8.l),
        0x86 => add_a_r(u16, gb, &gb.registers.named16.hl),
        0x87 => add_a_r(u8, gb, &gb.registers.named8.a),
        0x88 => adc_a_r(u8, gb, &gb.registers.named8.b),
        0x89 => adc_a_r(u8, gb, &gb.registers.named8.c),
        0x8a => adc_a_r(u8, gb, &gb.registers.named8.d),
        0x8b => adc_a_r(u8, gb, &gb.registers.named8.e),
        0x8c => adc_a_r(u8, gb, &gb.registers.named8.h),
        0x8d => adc_a_r(u8, gb, &gb.registers.named8.l),
        0x8e => adc_a_r(u16, gb, &gb.registers.named16.hl),
        0x8f => adc_a_r(u8, gb, &gb.registers.named8.a),

        0x90 => sub_a_r(u8, gb, &gb.registers.named8.b),
        0x91 => sub_a_r(u8, gb, &gb.registers.named8.c),
        0x92 => sub_a_r(u8, gb, &gb.registers.named8.d),
        0x93 => sub_a_r(u8, gb, &gb.registers.named8.e),
        0x94 => sub_a_r(u8, gb, &gb.registers.named8.h),
        0x95 => sub_a_r(u8, gb, &gb.registers.named8.l),
        0x96 => sub_a_r(u16, gb, &gb.registers.named16.hl),
        0x97 => sub_a_r(u8, gb, &gb.registers.named8.a),
        0x98 => sbc_a_r(u8, gb, &gb.registers.named8.b),
        0x99 => sbc_a_r(u8, gb, &gb.registers.named8.c),
        0x9a => sbc_a_r(u8, gb, &gb.registers.named8.d),
        0x9b => sbc_a_r(u8, gb, &gb.registers.named8.e),
        0x9c => sbc_a_r(u8, gb, &gb.registers.named8.h),
        0x9d => sbc_a_r(u8, gb, &gb.registers.named8.l),
        0x9e => sbc_a_r(u16, gb, &gb.registers.named16.hl),
        0x9f => sbc_a_r(u8, gb, &gb.registers.named8.a),

        0xa0 => and_a_r(u8, gb, &gb.registers.named8.b),
        0xa1 => and_a_r(u8, gb, &gb.registers.named8.c),
        0xa2 => and_a_r(u8, gb, &gb.registers.named8.d),
        0xa3 => and_a_r(u8, gb, &gb.registers.named8.e),
        0xa4 => and_a_r(u8, gb, &gb.registers.named8.h),
        0xa5 => and_a_r(u8, gb, &gb.registers.named8.l),
        0xa6 => and_a_r(u16, gb, &gb.registers.named16.hl),
        0xa7 => and_a_r(u8, gb, &gb.registers.named8.a),
        0xa8 => xor_a_r(u8, gb, &gb.registers.named8.b),
        0xa9 => xor_a_r(u8, gb, &gb.registers.named8.c),
        0xaa => xor_a_r(u8, gb, &gb.registers.named8.d),
        0xab => xor_a_r(u8, gb, &gb.registers.named8.e),
        0xac => xor_a_r(u8, gb, &gb.registers.named8.h),
        0xad => xor_a_r(u8, gb, &gb.registers.named8.l),
        0xae => xor_a_r(u16, gb, &gb.registers.named16.hl),
        0xaf => xor_a_r(u8, gb, &gb.registers.named8.a),

        0xb0 => or_a_r(u8, gb, &gb.registers.named8.b),
        0xb1 => or_a_r(u8, gb, &gb.registers.named8.c),
        0xb2 => or_a_r(u8, gb, &gb.registers.named8.d),
        0xb3 => or_a_r(u8, gb, &gb.registers.named8.e),
        0xb4 => or_a_r(u8, gb, &gb.registers.named8.h),
        0xb5 => or_a_r(u8, gb, &gb.registers.named8.l),
        0xb6 => or_a_r(u16, gb, &gb.registers.named16.hl),
        0xb7 => or_a_r(u8, gb, &gb.registers.named8.a),
        0xb8 => cp_a_r(u8, gb, &gb.registers.named8.b),
        0xb9 => cp_a_r(u8, gb, &gb.registers.named8.c),
        0xba => cp_a_r(u8, gb, &gb.registers.named8.d),
        0xbb => cp_a_r(u8, gb, &gb.registers.named8.e),
        0xbc => cp_a_r(u8, gb, &gb.registers.named8.h),
        0xbd => cp_a_r(u8, gb, &gb.registers.named8.l),
        0xbe => cp_a_r(u16, gb, &gb.registers.named16.hl),
        0xbf => cp_a_r(u8, gb, &gb.registers.named8.a),

        0xc0 => ret_cc(gb, !gb.registers.named8.f.z),
        0xc1 => pop_rr(gb, &gb.registers.named16.bc),
        0xc2 => jp_cc_a16(gb, !gb.registers.named8.f.z),
        0xc3 => jp_a16(gb),
        0xc4 => call_cc_a16(gb, !gb.registers.named8.f.z),
        0xc5 => push_rr(gb, &gb.registers.named16.bc),
        0xc6 => add_a_d8(gb),
        0xc7 => rst(gb, 0),
        0xc8 => ret_cc(gb, gb.registers.named8.f.z),
        0xc9 => ret(gb),
        0xca => jp_cc_a16(gb, gb.registers.named8.f.z),
        0xcb => illegal(),
        0xcc => call_cc_a16(gb, gb.registers.named8.f.z),
        0xcd => call_a16(gb),
        0xce => adc_a_d8(gb),
        0xcf => rst(gb, 1),

        0xd0 => ret_cc(gb, !gb.registers.named8.f.c),
        0xd1 => pop_rr(gb, &gb.registers.named16.de),
        0xd2 => jp_cc_a16(gb, !gb.registers.named8.f.c),
        0xd3 => illegal(),
        0xd4 => call_cc_a16(gb, !gb.registers.named8.f.c),
        0xd5 => push_rr(gb, &gb.registers.named16.de),
        0xd6 => sub_a_d8(gb),
        0xd7 => rst(gb, 2),
        0xd8 => ret_cc(gb, gb.registers.named8.f.c),
        0xd9 => reti(gb),
        0xda => jp_cc_a16(gb, gb.registers.named8.f.c),
        0xdb => illegal(),
        0xdc => call_cc_a16(gb, gb.registers.named8.f.c),
        0xdd => illegal(),
        0xde => sbc_a_d8(gb),
        0xdf => rst(gb, 3),

        0xe0 => ld_da8_a(gb),
        0xe1 => pop_rr(gb, &gb.registers.named16.hl),
        0xe2 => ld_dc_a(gb),
        0xe3 => illegal(),
        0xe4 => illegal(),
        0xe5 => push_rr(gb, &gb.registers.named16.hl),
        0xe6 => and_a_d8(gb),
        0xe7 => rst(gb, 4),
        0xe8 => add_sp_s8(gb),
        0xe9 => jp_hl(gb),
        0xea => ld_da16_a(gb),
        0xeb => illegal(),
        0xec => illegal(),
        0xed => illegal(),
        0xee => xor_a_d8(gb),
        0xef => rst(gb, 5),

        0xf0 => ld_a_da8(gb),
        0xf1 => pop_rr(gb, &gb.registers.named16.af),
        0xf2 => ld_a_dc(gb),
        0xf3 => di(gb),
        0xf4 => illegal(),
        0xf5 => push_rr(gb, &gb.registers.named16.af),
        0xf6 => or_a_d8(gb),
        0xf7 => rst(gb, 6),
        0xf8 => ld_hl_sp_s8(gb),
        0xf9 => ld_sp_hl(gb),
        0xfa => ld_a_da16(gb),
        0xfb => ei(gb),
        0xfc => illegal(),
        0xfd => illegal(),
        0xfe => cp_a_d8(gb),
        0xff => rst(gb, 7),
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
    cycleWrite(gb, rr.*, gb.registers.named8.a);
}

/// Increment the contents of register pair `rr` by 1.
fn inc_rr(gb: *gameboy.State, rr: *u16) void {
    gb.tick();
    rr.* +%= 1;
}

/// Increment the contents of register `r` by 1.
fn inc_r(gb: *gameboy.State, r: *u8) void {
    r.* +%= 1;

    gb.registers.named8.f.z = r.* == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = r.* & 0x0f == 0;
}

/// Decrement the contents of register `r` by 1.
fn dec_r(gb: *gameboy.State, r: *u8) void {
    r.* -%= 1;

    gb.registers.named8.f.z = r.* == 0;
    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = r.* & 0x0f == 0xf;
}

/// Load the 8-bit immediate operand d8 into register `r`.
fn ld_r_d8(gb: *gameboy.State, r: *u8) void {
    r.* = fetch8(gb);
}

/// Rotate the contents of register `A` to the left.
fn rlca(gb: *gameboy.State) void {
    const bit7 = (gb.registers.named8.a & 0x80) != 0;

    gb.registers.named8.a = (gb.registers.named8.a << 1) | @intFromBool(bit7);

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = bit7;
}

/// Store the lower byte of stack pointer `SP` at the address
/// specified by the 16-bit immediate operand a16 and the upper
/// byte of SP at address a16 + 1.
fn ld_da16_sp(gb: *gameboy.State) void {
    const addr: gameboy.Addr = fetch16(gb);

    cycleWrite(gb, addr, @intCast(gb.registers.named16.sp & 0x00ff));
    cycleWrite(gb, addr + 1, @intCast(gb.registers.named16.sp & 0xff00));
}

/// Add the contents of register pair `rr` to the contents of
/// register pair `HL` and store the results in `HL`.
fn add_hl_rr(gb: *gameboy.State, rr: *const u16) void {
    gb.tick();

    const value, const overflowed = @addWithOverflow(gb.registers.named16.hl, rr.*);
    gb.registers.named16.hl = value;

    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = @addWithOverflow(@as(u12, @truncate(gb.registers.named16.hl)), @as(u12, @truncate(rr.*)))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

/// Load the 8-bit contents of memory specified by register pair `rr`
/// into register `A`.
fn ld_a_drr(gb: *gameboy.State, rr: *const u16) void {
    gb.registers.named8.a = cycleRead(gb, rr.*);
}

/// Decrements the contenst of register pair `rr` by 1.
fn dec_rr(gb: *gameboy.State, rr: *u16) void {
    gb.tick();
    rr.* -%= 1;
}

/// Rotate the contents of register `A` to the right.
fn rrca(gb: *gameboy.State) void {
    const bit0 = (gb.registers.named8.a & 0x01) != 0;

    gb.registers.named8.a = @as(u8, @intFromBool(bit0)) << 7 | (gb.registers.named8.a >> 1);

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = bit0;
}

fn stop(gb: *gameboy.State) void {
    _ = gb;
}

/// Rotate the contents of register `A` to the left,
/// through the carry flag.
fn rla(gb: *gameboy.State) void {
    const bit7 = (gb.registers.named8.a & 0x80) != 0;

    gb.registers.named8.a =
        (gb.registers.named8.a << 1) | @intFromBool(gb.registers.named8.f.c);

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = bit7;
}

/// Jump `s8` steps from the current address in the program counter.
fn jr_s8(gb: *gameboy.State) void {
    jr_cc_s8(gb, true);
}

/// Rotate the contents of register `A` to the right,
/// through the carry flag.
fn rra(gb: *gameboy.State) void {
    const bit0 = (gb.registers.named8.a & 0x01) != 0;

    gb.registers.named8.a =
        @as(u8, @intFromBool(gb.registers.named8.f.c)) << 7 | (gb.registers.named8.a >> 1);

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = bit0;
}

/// Jump `s8` steps from the current address in the program counter
/// if the `condition` is true.
fn jr_cc_s8(gb: *gameboy.State, condition: bool) void {
    const offset: i8 = @bitCast(fetch8(gb));

    if (condition) {
        gb.tick();
        if (offset < 0) {
            gb.registers.named16.pc -%= @abs(offset);
        } else {
            gb.registers.named16.pc +%= @abs(offset);
        }
    }
}

/// Store the contents of register `A` into the memory location specified
/// by register pair `HL` and simultaneously increment `HL`.
fn ld_dhl_inc_a(gb: *gameboy.State) void {
    ld_dhl_r(gb, &gb.registers.named8.a);
    gb.registers.named16.hl +%= 1;
}

/// Adjust register `A` to a binary-coded decimal number after BCD
/// addition and subtraction operations.
fn daa(gb: *gameboy.State) void {
    const value, const overflowed =
        if (gb.registers.named8.f.n)
    result: {
        var adjustment: u8 = 0;

        if (gb.registers.named8.f.h) {
            adjustment += 0x06;
        }
        if (gb.registers.named8.f.c) {
            adjustment += 0x60;
        }

        break :result @subWithOverflow(gb.registers.named8.a, adjustment);
    } else result: {
        var adjustment: u8 = 0;

        if (gb.registers.named8.f.h or (gb.registers.named8.a & 0x0f) > 0x09) {
            adjustment += 0x06;
        }
        if (gb.registers.named8.f.c or (gb.registers.named8.a & 0x0f) > 0x99) {
            adjustment += 0x60;
        }

        break :result @addWithOverflow(gb.registers.named8.a, adjustment);
    };

    gb.registers.named8.a = value;
    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = overflowed == 1;
}

/// Load the contents of memory specified by register pair `HL` into
/// register `A` and simultaneously increment the contents of `HL`.
fn ld_a_dhl_inc(gb: *gameboy.State) void {
    ld_r_dhl(gb, &gb.registers.named8.a);
    gb.registers.named16.hl +%= 1;
}

/// Take the one's complement of the contents of register `A`.
fn cpl(gb: *gameboy.State) void {
    gb.registers.named8.a = ~gb.registers.named8.a;

    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = true;
}

/// Store the contents of register `A` into the memmory location specified
/// by the register pair `HL` and simultaneously decrement `HL`.
fn ld_dhl_dec_a(gb: *gameboy.State) void {
    ld_dhl_r(gb, &gb.registers.named8.a);
    gb.registers.named16.hl -%= 1;
}

/// Increment the contents of memory specified by register pair `HL` by 1.
fn inc_dhl(gb: *gameboy.State) void {
    const value = cycleRead(gb, gb.registers.named16.hl) +% 1;
    cycleWrite(gb, gb.registers.named16.hl, value);

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = value & 0x0f == 0;
}

/// Decrement the contents of memory specified by register pair `HL` by 1.
fn dec_dhl(gb: *gameboy.State) void {
    const value = cycleRead(gb, gb.registers.named16.hl) -% 1;
    cycleWrite(gb, gb.registers.named16.hl, value);

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = value & 0x0f == 0x0f;
}

/// Store the contents of 8-bit immediate operand d8 in the memory location
/// specified by register pair `HL`.
fn ld_dhl_d8(gb: *gameboy.State) void {
    const imm = fetch8(gb);
    cycleWrite(gb, gb.registers.named16.hl, imm);
}

/// Set the carry flag.
fn scf(gb: *gameboy.State) void {
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = true;
}

/// Load the contents of memory specified by register pair `HL` into register `A`
/// and simultaneously decrement `HL`.
fn ld_a_dhl_dec(gb: *gameboy.State) void {
    ld_r_dhl(gb, &gb.registers.named8.a);
    gb.registers.named16.hl -%= 1;
}

/// Flip the carry flag.
fn ccf(gb: *gameboy.State) void {
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = !gb.registers.named8.f.c;
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
    r.* = cycleRead(gb, gb.registers.named16.hl);
}

/// Store the contents of register `r` in the memory location specified
/// by register pair `HL`.
fn ld_dhl_r(gb: *gameboy.State, r: *const u8) void {
    cycleWrite(gb, gb.registers.named16.hl, r.*);
}

fn halt(gb: *gameboy.State) void {
    _ = gb;
}

/// Add the contents of register `r` or the memory pointed to by `r` to the
/// contents of register `A` and store the results in register `A`.
fn add_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    add_a_x(gb, src);
}

/// Add the contents of register `r` or the memory pointed to by `r` and the
/// carry flag to the contents of register `A` and store the results in `A`.
fn adc_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    adc_a_x(gb, src);
}

/// Subtract the contents of register `r` or the memory pointed to by `r` from the
/// contents of register `A` and store the results in register `A`.
fn sub_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    sub_a_x(gb, src);
}

/// Subtract the contents of register `r` or the memory pointed to by `r` and the
/// carry flag from the contents of register `A`, and store the results in `A`.
fn sbc_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    sbc_a_x(gb, src);
}

/// Take the bitwise AND of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn and_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    and_a_x(gb, src);
}

/// Take the bitwise XOR of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn xor_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    xor_a_x(gb, src);
}

/// Take the bitwise OR of register `r` or the memory pointed to by `r` and
/// register `A`, and store the results in `A`.
fn or_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
    or_a_x(gb, src);
}

/// Compare the contents of register `r` or the memory pointed to by `r` and
/// the contents of register `A` by calculating `A - B`, and set the `Z` flag
/// if they are equal.
fn cp_a_r(comptime T: type, gb: *gameboy.State, r: *const T) void {
    const src = getSrc(T, gb, r);
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
    const lo = cycleRead(gb, gb.registers.named16.sp);
    gb.registers.named16.sp +%= 1;
    const hi = cycleRead(gb, gb.registers.named16.sp);
    gb.registers.named16.sp +%= 1;

    rr.* = @as(u16, hi) << 8 | lo;
}

/// Load the 16-bit immediate operand `a16` into the program counter if
/// the `condition` is true. If the `condition` is true, then the subsequent
/// instruction starts at address `a16`. If not, the contents of `PC` are
/// incremented, and the next instruction following the current JP instruction
/// is executed (as usual).
fn jp_cc_a16(gb: *gameboy.State, condition: bool) void {
    const addr: gameboy.Addr = fetch16(gb);

    if (condition) {
        gb.tick();
        gb.registers.named16.pc = addr;
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
    const addr: gameboy.Addr = fetch16(gb);

    if (condition) {
        push_rr(gb, &gb.registers.named16.pc);
        gb.registers.named16.pc = addr;
    }
}

/// Push the contents of register pair `rr` onto the memory stack.
fn push_rr(gb: *gameboy.State, rr: *const u16) void {
    gb.tick();

    gb.registers.named16.sp -%= 1;
    cycleWrite(gb, gb.registers.named16.sp, @intCast(rr.* & 0xff00));
    gb.registers.named16.sp -%= 1;
    cycleWrite(gb, gb.registers.named16.sp, @intCast(rr.* & 0x00ff));
}

/// Add the contents of the 8-bit immediate operand `d8` to the contents of register `A`,
/// and store the results in `A`.
fn add_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    add_a_x(gb, src);
}

/// Push the current value of the program counter onto the memory stack, and
/// load into `PC` the nth byte of page 0 memory addresses.
fn rst(gb: *gameboy.State, comptime n: u8) void {
    push_rr(gb, &gb.registers.named16.pc);
    gb.registers.named16.pc = n * 0x08;
}

/// Pop from the memory stack the program counter value pushed when the
/// subroutine was called, returning control to the source program.
fn ret(gb: *gameboy.State) void {
    gb.tick();
    pop_rr(gb, &gb.registers.named16.pc);
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
    gb.ime = true;
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
    cycleWrite(gb, @as(u16, 0xff00) + imm, gb.registers.named8.a);
}

/// Store the contents of register `A` in the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by register `C`.
fn ld_dc_a(gb: *gameboy.State) void {
    cycleWrite(gb, @as(u16, 0xff00) + gb.registers.named8.c, gb.registers.named8.a);
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
    const value, const overflowed = if (offset < 0) result: {
        break :result @subWithOverflow(gb.registers.named16.sp, @abs(offset));
    } else result: {
        break :result @addWithOverflow(gb.registers.named16.sp, @abs(offset));
    };
    gb.registers.named16.sp = value;

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h =
        @addWithOverflow(@as(u4, @truncate(gb.registers.named16.sp)), @as(u4, @truncate(@as(u8, @bitCast(offset)))))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

/// Load the contents of register pair `HL` into the program counter. The next instruction
/// is fetched from the location specified by the new value of `PC`.
fn jp_hl(gb: *gameboy.State) void {
    gb.registers.named16.pc = gb.registers.named16.hl;
}

/// Add the 8-bit signed operand `s8` (values -128 to +127) to the stack pointer `SP`,
/// and store the result in register pair `HL`.
fn ld_hl_sp_s8(gb: *gameboy.State) void {
    gb.tick();

    const offset: i8 = @bitCast(fetch8(gb));
    const value, const overflowed = if (offset < 0) result: {
        break :result @subWithOverflow(gb.registers.named16.sp, @abs(offset));
    } else result: {
        break :result @addWithOverflow(gb.registers.named16.sp, @abs(offset));
    };
    gb.registers.named16.hl = value;

    gb.registers.named8.f.z = false;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h =
        @addWithOverflow(@as(u4, @truncate(gb.registers.named16.sp)), @as(u4, @truncate(@as(u8, @bitCast(offset)))))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

/// Load the contents of register pair `HL` into the stack pointer `SP`.
fn ld_sp_hl(gb: *gameboy.State) void {
    gb.tick();
    gb.registers.named16.sp = gb.registers.named16.hl;
}

/// Store the contents of register `A` in the internal RAM or register specified by
/// the 16-bit immediate operand `a16`.
fn ld_da16_a(gb: *gameboy.State) void {
    const addr: gameboy.Addr = fetch16(gb);
    cycleWrite(gb, addr, gb.registers.named8.a);
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
    gb.registers.named8.a = cycleRead(gb, @as(u16, 0xff00) + imm);
}

/// Load into register `A` the contents of the internal RAM, port register, or mode
/// register at the address in the range `0xFF00`-`0xFFFF` specified by register `C`.
fn ld_a_dc(gb: *gameboy.State) void {
    gb.registers.named8.a = cycleRead(gb, @as(u16, 0xff00) + gb.registers.named8.c);
}

/// Reset the interrupt master enable flag and prohibit maskable interrupts.
///
/// Cancels any scheduled effects of the EI instruction.
fn di(gb: *gameboy.State) void {
    gb.ime = false;
    gb.scheduled_ei = false;
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
    const addr: gameboy.Addr = fetch16(gb);
    gb.registers.named8.a = cycleRead(gb, addr);
}

/// Set the interrupt master enable flag and enable maskable interrupts. This
/// instruction can be used in an interrupt routine to enable higher-order interrupts.
///
/// The flag is only set *after* the instruction following EI.
fn ei(gb: *gameboy.State) void {
    gb.scheduled_ei = true;
}

/// Compare the contents of register `A` and the contents of the 8-bit immediate
/// operand `d8` by calculating `A - d8`, and set the `Z` flag if they are equal.
fn cp_a_d8(gb: *gameboy.State) void {
    const src = fetch8(gb);
    cp_a_x(gb, src);
}

fn illegal() void {
    // TODO: handle
}

fn add_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @addWithOverflow(gb.registers.named8.a, src);
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = @addWithOverflow(@as(u4, @truncate(gb.registers.named8.a)), @as(u4, @truncate(src)))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

fn adc_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflow = addManyWithOverflow(u8, 3, [_]u8{
        gb.registers.named8.a,
        src,
        @intFromBool(gb.registers.named8.f.c),
    });
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = addManyWithOverflow(u4, 3, [_]u4{
        @as(u4, @truncate(gb.registers.named8.a)),
        @as(u4, @truncate(src)),
        @intFromBool(gb.registers.named8.f.c),
    })[1];
    gb.registers.named8.f.c = overflow;
}

fn sub_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @subWithOverflow(gb.registers.named8.a, src);
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = @subWithOverflow(@as(u4, @truncate(gb.registers.named8.a)), @as(u4, @truncate(src)))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

fn sbc_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = subManyWithOverflow(u8, 3, [_]u8{ gb.registers.named8.a, src, @intFromBool(gb.registers.named8.f.c) });
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = subManyWithOverflow(u4, 3, [_]u4{
        @as(u4, @truncate(gb.registers.named8.a)),
        @as(u4, @truncate(src)),
        @intFromBool(gb.registers.named8.f.c),
    })[1];
    gb.registers.named8.f.c = overflowed;
}

fn and_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.registers.named8.a & src;
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = true;
    gb.registers.named8.f.c = false;
}

fn xor_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.registers.named8.a ^ src;
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = false;
}

fn or_a_x(gb: *gameboy.State, src: u8) void {
    const value = gb.registers.named8.a | src;
    gb.registers.named8.a = value;

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = false;
    gb.registers.named8.f.h = false;
    gb.registers.named8.f.c = false;
}

fn cp_a_x(gb: *gameboy.State, src: u8) void {
    const value, const overflowed = @subWithOverflow(gb.registers.named8.a, src);

    gb.registers.named8.f.z = value == 0;
    gb.registers.named8.f.n = true;
    gb.registers.named8.f.h = @subWithOverflow(@as(u4, @truncate(gb.registers.named8.a)), @as(u4, @truncate(src)))[1] == 1;
    gb.registers.named8.f.c = overflowed == 1;
}

/// Fetches 16 bits from the memory pointed to by `PC`, incrementing `PC` twice.
fn fetch16(gb: *gameboy.State) u16 {
    const lo = fetch8(gb);
    const hi = fetch8(gb);

    return @as(u16, hi) << 8 | lo;
}

/// Fetches 8 bits from the memory pointed to by `PC` and incrementing `PC`.
fn fetch8(gb: *gameboy.State) u8 {
    const value = cycleRead(gb, gb.registers.named16.pc);
    gb.registers.named16.pc +%= 1;

    return value;
}

fn cycleRead(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    gb.tick();

    // TODO: read from memory
    _ = addr; // autofix

    return 0;
}

fn cycleWrite(gb: *gameboy.State, addr: gameboy.Addr, value: u8) void {
    gb.tick();

    // TODO: write to memory
    _ = addr; // autofix
    _ = value; // autofix
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

/// Either reads from `r` if it is an 8-bit register or reads from
/// the memory pointed to by `r` if it is a 16-bit register.
fn getSrc(comptime T: type, gb: *gameboy.State, r: *const T) u8 {
    return switch (T) {
        u8 => r.*,
        u16 => cycleRead(gb, r.*),
        else => @compileError("unsupported type"),
    };
}

test "exec nop" {
    // TODO: fill memory state and check state after exec
    var gb = gameboy.State{
        .ime = false,
        .scheduled_ei = false,
        .registers = .{ .arr16 = [_]u16{0} ** 6 },
    };
    exec(&gb);
}
