const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// 16-bit address to index ROM, RAM, and I/O.
pub const Addr = u16;

const VRAM_START = 0x8000;
const RAM_START = 0xc000;
const OAM_START = 0xfe00;
const HRAM_START = 0xff80;

/// Reads a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn readByte(gb: *gameboy.State, addr: Addr) u8 {
    return switch (addr) {
        0x0000...0x3fff => read_rom(gb, addr),
        0x4000...0x7fff => read_mbc_rom(gb, addr),
        0x8000...0x9fff => read_vram(gb, addr),
        0xa000...0xbfff => read_mbc_ram(gb, addr),
        0xc000...0xcfff => read_ram(gb, addr),
        0xd000...0xdfff => read_banked_ram(gb, addr),
        0xe000...0xfdff => read_ram(gb, addr),
        0xfe00...0xfe9f => read_oam(gb, addr),
        0xfea0...0xfeff => read_not_usable(gb, addr),
        0xff00...0xff7f => read_io_registers(gb, addr),
        0xff80...0xfffe => read_hram(gb, addr),
        0xffff => read_ie(gb, addr),
    };
}

fn read_rom(gb: *gameboy.State, addr: Addr) u8 {
    // TODO: track if rom is finished
    if (addr < 0x100) {
        return gb.boot_rom[addr];
    }

    if (gb.rom) |rom| {
        return rom[addr];
    }

    return 0xff;
}

fn read_mbc_rom(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_vram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.vram[addr - VRAM_START];
}

fn read_mbc_ram(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_ram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.ram[addr - RAM_START];
}

fn read_banked_ram(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_oam(gb: *gameboy.State, addr: Addr) u8 {
    return gb.oam[addr - OAM_START];
}

fn read_not_usable(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_io_registers(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_hram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.hram[addr - HRAM_START];
}

fn read_ie(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

/// Writes a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn writeByte(gb: *gameboy.State, addr: Addr, value: u8) void {
    return switch (addr) {
        0x0000...0x3fff => write_rom(gb, addr, value),
        0x4000...0x7fff => write_mbc_rom(gb, addr, value),
        0x8000...0x9fff => write_vram(gb, addr, value),
        0xa000...0xbfff => write_mbc_ram(gb, addr, value),
        0xc000...0xcfff => write_ram(gb, addr, value),
        0xd000...0xdfff => write_banked_ram(gb, addr, value),
        0xe000...0xfdff => write_ram(gb, addr, value),
        0xfe00...0xfe9f => write_oam(gb, addr, value),
        0xfea0...0xfeff => write_not_usable(gb, addr, value),
        0xff00...0xff7f => write_io_registers(gb, addr, value),
        0xff80...0xfffe => write_hram(gb, addr, value),
        0xffff => write_ie(gb, addr, value),
    };
}

fn write_rom(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_mbc_rom(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_vram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.vram[addr - VRAM_START] = value;
}

fn write_mbc_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.ram[addr - RAM_START] = value;
}

fn write_banked_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_oam(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.oam[addr - OAM_START] = value;
}

fn write_not_usable(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_io_registers(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_hram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.hram[addr - HRAM_START] = value;
}

fn write_ie(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

test "read byte" {
    // TODO: fill memory state and check state after read
    var gb = try gameboy.State.init(testing.allocator);
    defer gb.free(testing.allocator);

    _ = readByte(&gb, 0);
}
