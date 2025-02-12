const std = @import("std");
const gameboy = @import("gb.zig");
const testing = std.testing;

/// Executes a single CPU instruction.
pub fn exec(gb: *gameboy.State) void {
    const op_code = gb.fetch_op_code();
    switch (op_code) {
        0x00 => nop(),
        0x01 => ld_rr_d16(gb, &gb.registers.named16.bc),
        0x02 => ld_drr_a(gb, &gb.registers.named16.bc),
        0x03 => inc_rr(&gb.registers.named16.bc),
        0x04 => inc_r(&gb.registers.named8.b),
        0x05 => dec_r(&gb.registers.named8.b),
        0x06 => ld_r_d8(&gb.registers.named8.b),
        0x07 => rlca(gb),
        0x08 => ld_da16_sp(gb),
        0x09 => add_hl_rr(gb, &gb.registers.named16.bc),
        0x0a => ld_a_drr(gb, &gb.registers.named16.bc),
        0x0b => dec_rr(&gb.registers.named16.bc),
        0x0c => inc_r(&gb.registers.named8.c),
        0x0d => dec_r(&gb.registers.named8.c),
        0x0e => ld_r_d8(&gb.registers.named8.c),
        0x0f => rrca(gb),

        0x10 => stop(gb),
        0x11 => ld_rr_d16(gb, &gb.registers.named16.de),
        0x12 => ld_drr_a(gb, &gb.registers.named16.de),
        0x13 => inc_rr(&gb.registers.named16.de),
        0x14 => inc_r(&gb.registers.named8.d),
        0x15 => dec_r(&gb.registers.named8.d),
        0x16 => ld_r_d8(&gb.registers.named8.d),
        0x17 => rla(gb),
        0x18 => jr_r8(gb),
        0x19 => add_hl_rr(gb, &gb.registers.named16.de),
        0x1a => ld_a_drr(gb, &gb.registers.named16.de),
        0x1b => dec_rr(&gb.registers.named16.de),
        0x1c => inc_r(&gb.registers.named8.e),
        0x1d => dec_r(&gb.registers.named8.e),
        0x1e => ld_r_d8(&gb.registers.named8.e),
        0x1f => rra(gb),

        0x20 => jr_cc_r8(gb, !gb.registers.named8.f.z),
        0x21 => ld_rr_d16(gb, &gb.registers.named16.hl),
        0x22 => ld_dhl_inc_a(gb),
        0x23 => inc_rr(&gb.registers.named16.hl),
        0x24 => inc_r(&gb.registers.named8.h),
        0x25 => dec_r(&gb.registers.named8.h),
        0x26 => ld_r_d8(&gb.registers.named8.h),
        0x27 => daa(gb),
        0x28 => jr_cc_r8(gb, gb.registers.named8.f.z),
        0x29 => add_hl_rr(gb, &gb.registers.named16.hl),
        0x2a => ld_a_dhl_inc(gb),
        0x2b => dec_rr(&gb.registers.named16.hl),
        0x2c => inc_r(&gb.registers.named8.l),
        0x2d => dec_r(&gb.registers.named8.l),
        0x2e => ld_r_d8(&gb.registers.named8.l),
        0x2f => cpl(gb),

        0x30 => jr_cc_r8(gb, !gb.registers.named8.f.c),
        0x31 => ld_rr_d16(gb, &gb.registers.named16.sp),
        0x32 => ld_dhl_dec_a(gb),
        0x33 => inc_rr(&gb.registers.named16.sp),
        0x34 => inc_dhl(gb),
        0x35 => dec_dhl(gb),
        0x36 => ld_dhl_d8(gb),
        0x37 => scf(gb),
        0x38 => jr_cc_r8(gb, gb.registers.named8.f.c),
        0x39 => add_hl_rr(gb, &gb.registers.named16.sp),
        0x3a => ld_a_dhl_dec(gb),
        0x3b => dec_rr(&gb.registers.named16.sp),
        0x3c => inc_r(&gb.registers.named8.a),
        0x3d => dec_r(&gb.registers.named8.a),
        0x3e => ld_r_d8(&gb.registers.named8.a),
        0x3f => ccf(gb),

        0x40 => breakpoint(gb),
        0x41 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.c),
        0x42 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.d),
        0x43 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.e),
        0x44 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.h),
        0x45 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.l),
        0x46 => ld_r_dhl(&gb.registers.named8.b),
        0x47 => ld_r_r(&gb.registers.named8.b, &gb.registers.named8.a),
        0x48 => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.b),
        0x49 => nop(),
        0x4a => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.d),
        0x4b => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.e),
        0x4c => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.h),
        0x4d => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.l),
        0x4e => ld_r_dhl(&gb.registers.named8.c),
        0x4f => ld_r_r(&gb.registers.named8.c, &gb.registers.named8.a),

        0x50 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.b),
        0x51 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.c),
        0x52 => nop(),
        0x53 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.e),
        0x54 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.h),
        0x55 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.l),
        0x56 => ld_r_dhl(&gb.registers.named8.d),
        0x57 => ld_r_r(&gb.registers.named8.d, &gb.registers.named8.a),
        0x58 => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.b),
        0x59 => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.c),
        0x5a => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.d),
        0x5b => nop(),
        0x5c => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.h),
        0x5d => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.l),
        0x5e => ld_r_dhl(&gb.registers.named8.e),
        0x5f => ld_r_r(&gb.registers.named8.e, &gb.registers.named8.a),

        0x60 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.b),
        0x61 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.c),
        0x62 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.d),
        0x63 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.e),
        0x64 => nop(),
        0x65 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.l),
        0x66 => ld_r_dhl(&gb.registers.named8.h),
        0x67 => ld_r_r(&gb.registers.named8.h, &gb.registers.named8.a),
        0x68 => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.b),
        0x69 => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.c),
        0x6a => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.d),
        0x6b => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.e),
        0x6c => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.h),
        0x6d => nop(),
        0x6e => ld_r_dhl(&gb.registers.named8.l),
        0x6f => ld_r_r(&gb.registers.named8.l, &gb.registers.named8.a),

        0x70 => ld_dhl_r(&gb.registers.named8.b),
        0x71 => ld_dhl_r(&gb.registers.named8.c),
        0x72 => ld_dhl_r(&gb.registers.named8.d),
        0x73 => ld_dhl_r(&gb.registers.named8.e),
        0x74 => ld_dhl_r(&gb.registers.named8.h),
        0x75 => ld_dhl_r(&gb.registers.named8.l),
        0x76 => halt(gb),
        0x77 => ld_dhl_r(&gb.registers.named8.a),
        0x78 => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.b),
        0x79 => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.c),
        0x7a => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.d),
        0x7b => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.e),
        0x7c => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.h),
        0x7d => ld_r_r(&gb.registers.named8.a, &gb.registers.named8.l),
        0x7e => ld_r_dhl(&gb.registers.named8.a),
        0x7f => nop(),

        0x80 => add_a_r(&gb.registers.named8.b),
        0x81 => add_a_r(&gb.registers.named8.c),
        0x82 => add_a_r(&gb.registers.named8.d),
        0x83 => add_a_r(&gb.registers.named8.e),
        0x84 => add_a_r(&gb.registers.named8.h),
        0x85 => add_a_r(&gb.registers.named8.l),
        0x86 => add_a_dhl(gb),
        0x87 => add_a_r(&gb.registers.named8.a),
        0x88 => adc_a_r(&gb.registers.named8.b),
        0x89 => adc_a_r(&gb.registers.named8.c),
        0x8a => adc_a_r(&gb.registers.named8.d),
        0x8b => adc_a_r(&gb.registers.named8.e),
        0x8c => adc_a_r(&gb.registers.named8.h),
        0x8d => adc_a_r(&gb.registers.named8.l),
        0x8e => adc_a_dhl(gb),
        0x8f => adc_a_r(&gb.registers.named8.a),

        0x90 => sub_a_r(&gb.registers.named8.b),
        0x91 => sub_a_r(&gb.registers.named8.c),
        0x92 => sub_a_r(&gb.registers.named8.d),
        0x93 => sub_a_r(&gb.registers.named8.e),
        0x94 => sub_a_r(&gb.registers.named8.h),
        0x95 => sub_a_r(&gb.registers.named8.l),
        0x96 => sub_a_dhl(gb),
        0x97 => sub_a_r(&gb.registers.named8.a),
        0x98 => sbc_a_r(&gb.registers.named8.b),
        0x99 => sbc_a_r(&gb.registers.named8.c),
        0x9a => sbc_a_r(&gb.registers.named8.d),
        0x9b => sbc_a_r(&gb.registers.named8.e),
        0x9c => sbc_a_r(&gb.registers.named8.h),
        0x9d => sbc_a_r(&gb.registers.named8.l),
        0x9e => sbc_a_dhl(gb),
        0x9f => sbc_a_r(&gb.registers.named8.a),

        0xa0 => and_a_r(&gb.registers.named8.b),
        0xa1 => and_a_r(&gb.registers.named8.c),
        0xa2 => and_a_r(&gb.registers.named8.d),
        0xa3 => and_a_r(&gb.registers.named8.e),
        0xa4 => and_a_r(&gb.registers.named8.h),
        0xa5 => and_a_r(&gb.registers.named8.l),
        0xa6 => and_a_dhl(gb),
        0xa7 => and_a_r(&gb.registers.named8.a),
        0xa8 => xor_a_r(&gb.registers.named8.b),
        0xa9 => xor_a_r(&gb.registers.named8.c),
        0xaa => xor_a_r(&gb.registers.named8.d),
        0xab => xor_a_r(&gb.registers.named8.e),
        0xac => xor_a_r(&gb.registers.named8.h),
        0xad => xor_a_r(&gb.registers.named8.l),
        0xae => xor_a_dhl(gb),
        0xaf => xor_a_r(&gb.registers.named8.a),

        0xb0 => or_a_r(&gb.registers.named8.b),
        0xb1 => or_a_r(&gb.registers.named8.c),
        0xb2 => or_a_r(&gb.registers.named8.d),
        0xb3 => or_a_r(&gb.registers.named8.e),
        0xb4 => or_a_r(&gb.registers.named8.h),
        0xb5 => or_a_r(&gb.registers.named8.l),
        0xb6 => or_a_dhl(gb),
        0xb7 => or_a_r(&gb.registers.named8.a),
        0xb8 => cp_a_r(&gb.registers.named8.b),
        0xb9 => cp_a_r(&gb.registers.named8.c),
        0xba => cp_a_r(&gb.registers.named8.d),
        0xbb => cp_a_r(&gb.registers.named8.e),
        0xbc => cp_a_r(&gb.registers.named8.h),
        0xbd => cp_a_r(&gb.registers.named8.l),
        0xbe => cp_a_dhl(gb),
        0xbf => cp_a_r(&gb.registers.named8.a),

        0xc0 => ret_cc(gb, !gb.registers.named8.f.z),
        0xc1 => pop_rr(&gb.registers.named16.bc),
        0xc2 => jp_cc_a16(gb, !gb.registers.named8.f.z),
        0xc3 => jp_a16(gb),
        0xc4 => call_cc_a16(gb, !gb.registers.named8.f.z),
        0xc5 => push_rr(&gb.registers.named16.bc),
        0xc6 => add_a_d8(gb),
        0xc7 => rst(gb, 0x00),
        0xc8 => ret_cc(gb, gb.registers.named8.f.z),
        0xc9 => ret(gb),
        0xca => jp_cc_a16(gb, gb.registers.named8.f.z),
        0xcb => illegal(),
        0xcc => call_cc_a16(gb, gb.registers.named8.f.z),
        0xcd => call_a16(gb),
        0xce => adc_a_d8(gb),
        0xcf => rst(gb, 0x08),

        0xd0 => ret_cc(gb, !gb.registers.named8.f.c),
        0xd1 => pop_rr(&gb.registers.named16.de),
        0xd2 => jp_cc_a16(gb, !gb.registers.named8.f.c),
        0xd3 => illegal(),
        0xd4 => call_cc_a16(gb, !gb.registers.named8.f.c),
        0xd5 => push_rr(&gb.registers.named16.de),
        0xd6 => sub_a_d8(gb),
        0xd7 => rst(gb, 0x10),
        0xd8 => ret_cc(gb, gb.registers.named8.f.c),
        0xd9 => reti(gb),
        0xda => jp_cc_a16(gb, gb.registers.named8.f.c),
        0xdb => illegal(),
        0xdc => call_cc_a16(gb, gb.registers.named8.f.c),
        0xdd => illegal(),
        0xde => sbc_a_d8(gb),
        0xdf => rst(gb, 0x18),

        0xe0 => ld_da8_a(gb),
        0xe1 => pop_rr(&gb.registers.named16.hl),
        0xe2 => ld_dc_a(gb),
        0xe3 => illegal(),
        0xe4 => illegal(),
        0xe5 => push_rr(&gb.registers.named16.hl),
        0xe6 => and_a_d8(gb),
        0xe7 => rst(gb, 0x20),
        0xe8 => add_sp_r8(gb),
        0xe9 => jp_hl(gb),
        0xea => ld_da16_a(gb),
        0xeb => illegal(),
        0xec => illegal(),
        0xed => illegal(),
        0xee => xor_a_d8(gb),
        0xef => rst(gb, 0x28),

        0xf0 => ld_a_da8(gb),
        0xf1 => pop_rr(&gb.registers.named16.af),
        0xf2 => ld_a_dc(gb),
        0xf3 => di(gb),
        0xf4 => illegal(),
        0xf5 => push_rr(&gb.registers.named16.af),
        0xf6 => or_a_d8(gb),
        0xf7 => rst(gb, 0x30),
        0xf8 => ld_hl_sp_r8(gb),
        0xf9 => ld_sp_hl(gb),
        0xfa => ld_a_da16(gb),
        0xfb => ei(gb),
        0xfc => illegal(),
        0xfd => illegal(),
        0xfe => cp_a_d8(gb),
        0xff => rst(gb, 0x38),
    }
}

fn nop() void {}

fn ld_rr_d16(gb: *gameboy.State, rr: *u16) void {
    const value = gb.fetch_d16();
    rr.* = value;
}

fn ld_drr_a(gb: *gameboy.State, rr: *u16) void {
    _ = gb;
    _ = rr;
}

fn inc_rr(rr: *u16) void {
    _ = rr;
}

fn inc_r(r: *u8) void {
    _ = r;
}

fn dec_r(r: *u8) void {
    _ = r;
}

fn ld_r_d8(r: *u8) void {
    _ = r;
}

fn rlca(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_da16_sp(gb: *gameboy.State) void {
    _ = gb;
}

fn add_hl_rr(gb: *gameboy.State, rr: *u16) void {
    _ = gb;
    _ = rr;
}

fn ld_a_drr(gb: *gameboy.State, rr: *u16) void {
    _ = gb;
    _ = rr;
}

fn dec_rr(rr: *u16) void {
    _ = rr;
}

fn rrca(gb: *gameboy.State) void {
    _ = gb;
}

fn stop(gb: *gameboy.State) void {
    _ = gb;
}

fn rla(gb: *gameboy.State) void {
    _ = gb;
}

fn jr_r8(gb: *gameboy.State) void {
    _ = gb;
}

fn rra(gb: *gameboy.State) void {
    _ = gb;
}

fn jr_cc_r8(gb: *gameboy.State, condition: bool) void {
    _ = gb;
    _ = condition;
}

fn ld_dhl_inc_a(gb: *gameboy.State) void {
    _ = gb;
}

fn daa(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_a_dhl_inc(gb: *gameboy.State) void {
    _ = gb;
}

fn cpl(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_dhl_dec_a(gb: *gameboy.State) void {
    _ = gb;
}

fn inc_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn dec_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_dhl_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn scf(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_a_dhl_dec(gb: *gameboy.State) void {
    _ = gb;
}

fn ccf(gb: *gameboy.State) void {
    _ = gb;
}

fn breakpoint(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_r_r(r1: *u8, r2: *u8) void {
    _ = r1;
    _ = r2;
}

fn ld_r_dhl(r: *u8) void {
    _ = r;
}

fn ld_dhl_r(r: *u8) void {
    _ = r;
}

fn halt(gb: *gameboy.State) void {
    _ = gb;
}

fn add_a_r(r: *u8) void {
    _ = r;
}

fn add_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn adc_a_r(r: *u8) void {
    _ = r;
}

fn adc_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn sub_a_r(r: *u8) void {
    _ = r;
}

fn sub_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn sbc_a_r(r: *u8) void {
    _ = r;
}

fn sbc_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn and_a_r(r: *u8) void {
    _ = r;
}

fn and_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn xor_a_r(r: *u8) void {
    _ = r;
}

fn xor_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn or_a_r(r: *u8) void {
    _ = r;
}

fn or_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn cp_a_r(r: *u8) void {
    _ = r;
}

fn cp_a_dhl(gb: *gameboy.State) void {
    _ = gb;
}

fn ret_cc(gb: *gameboy.State, condition: bool) void {
    _ = gb;
    _ = condition;
}

fn pop_rr(rr: *u16) void {
    _ = rr;
}

fn jp_cc_a16(gb: *gameboy.State, condition: bool) void {
    _ = gb;
    _ = condition;
}

fn jp_a16(gb: *gameboy.State) void {
    _ = gb;
}

fn call_cc_a16(gb: *gameboy.State, condition: bool) void {
    _ = gb;
    _ = condition;
}

fn push_rr(rr: *u16) void {
    _ = rr;
}

fn add_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn rst(gb: *gameboy.State, value: u8) void {
    _ = gb;
    _ = value;
}

fn ret(gb: *gameboy.State) void {
    _ = gb;
}

fn call_a16(gb: *gameboy.State) void {
    _ = gb;
}

fn adc_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn sub_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn reti(gb: *gameboy.State) void {
    _ = gb;
}

fn sbc_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_da8_a(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_dc_a(gb: *gameboy.State) void {
    _ = gb;
}

fn and_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn add_sp_r8(gb: *gameboy.State) void {
    _ = gb;
}

fn jp_hl(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_hl_sp_r8(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_sp_hl(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_da16_a(gb: *gameboy.State) void {
    _ = gb;
}

fn xor_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_a_da8(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_a_dc(gb: *gameboy.State) void {
    _ = gb;
}

fn di(gb: *gameboy.State) void {
    _ = gb;
}

fn or_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn ld_a_da16(gb: *gameboy.State) void {
    _ = gb;
}

fn ei(gb: *gameboy.State) void {
    _ = gb;
}

fn cp_a_d8(gb: *gameboy.State) void {
    _ = gb;
}

fn illegal() void {
    // TODO: handle
}

test "exec nop" {
    // TODO: fill memory state and check state after exec
    var gb = gameboy.State{ .registers = .{ .arr16 = [_]u16{0} ** 6 } };
    exec(&gb);
}
