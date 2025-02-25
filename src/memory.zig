const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

pub fn readByte(gb: *gameboy.State, addr: gameboy.Addr) u8 {
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

fn read_rom(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_mbc_rom(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_vram(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_mbc_ram(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_ram(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_banked_ram(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_oam(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_not_usable(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_io_registers(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_hram(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

fn read_ie(gb: *gameboy.State, addr: gameboy.Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    return 0;
}

pub fn writeByte(gb: *gameboy.State, addr: gameboy.Addr, value: u8) void {
    gb.bus.memory[addr] = value;
}

test "read byte" {
    // TODO: fill memory state and check state after read
    var gb = try gameboy.State.init(testing.allocator);
    defer gb.free(testing.allocator);

    _ = readByte(&gb, 0);
}
