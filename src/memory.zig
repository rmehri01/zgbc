const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// 16-bit address to index ROM, RAM, and I/O.
pub const Addr = u16;

pub const VRAM_START = 0x8000;
pub const TILE_BLOCK0_START = 0x8000;
pub const TILE_BLOCK1_START = 0x8800;
pub const TILE_BLOCK2_START = 0x9000;
pub const TILE_MAP0_START = 0x9800;
pub const TILE_MAP1_START = 0x9c00;
pub const RAM_START = 0xc000;
pub const OAM_START = 0xfe00;
pub const HRAM_START = 0xff80;

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
        // TODO: clean up
        0xe000...0xfdff => read_ram(gb, addr - 0x2000),
        0xfe00...0xfe9f => read_oam(gb, addr),
        0xfea0...0xfeff => read_not_usable(gb, addr),
        0xff00...0xff7f => read_io_registers(gb, addr),
        0xff80...0xfffe => read_hram(gb, addr),
        0xffff => read_ie(gb),
    };
}

fn read_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (!gb.io_registers.boot_rom_finished and addr < 0x100) {
        return gb.boot_rom[addr];
    }

    if (gb.rom) |rom| {
        return rom[addr];
    }

    return 0xff;
}

fn read_mbc_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (gb.rom) |rom| {
        return rom[addr];
    }

    return 0xff;
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
    return gb.ram[addr - RAM_START];
}

fn read_oam(gb: *gameboy.State, addr: Addr) u8 {
    return gb.oam[addr - OAM_START];
}

fn read_not_usable(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    // TODO: oam corruption
    // return 0;
    @panic("unimplemented");
}

fn read_io_registers(gb: *gameboy.State, addr: Addr) u8 {
    return switch (addr) {
        0xff00 => value: {
            const nibble = if (gb.io_registers.joyp.select_d_pad == 0)
                gb.button_state.nibbles.d_pad
            else if (gb.io_registers.joyp.select_buttons == 0)
                gb.button_state.nibbles.buttons
            else
                0xf;
            break :value @as(u8, 0b11) << 6 |
                @as(u8, @as(u2, @bitCast(gb.io_registers.joyp))) << 4 |
                nibble;
        },
        0xff04 => gb.io_registers.div,
        0xff05 => gb.io_registers.tima,
        0xff06 => gb.io_registers.tma,
        0xff07 => @bitCast(gb.io_registers.tac),
        0xff0f => @bitCast(gb.io_registers.intf),
        0xff40 => @bitCast(gb.io_registers.lcdc),
        0xff41 => @bitCast(gb.io_registers.stat),
        0xff42 => gb.io_registers.scy,
        0xff43 => gb.io_registers.scx,
        0xff44 => gb.io_registers.ly,
        0xff45 => gb.io_registers.lyc,
        0xff46 => gb.io_registers.dma,
        0xff47 => @bitCast(gb.io_registers.bgp),
        0xff48 => @bitCast(gb.io_registers.obp0),
        0xff49 => @bitCast(gb.io_registers.obp1),
        0xff50 => @as(u8, 0xfe) | @intFromBool(gb.io_registers.boot_rom_finished),
        else => 0xff,
    };
}

fn read_hram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.hram[addr - HRAM_START];
}

fn read_ie(gb: *gameboy.State) u8 {
    return @bitCast(gb.io_registers.ie);
}

/// Writes a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn writeByte(gb: *gameboy.State, addr: Addr, value: u8) void {
    return switch (addr) {
        0x0000...0x7fff => write_mbc_rom(gb, addr, value),
        0x8000...0x9fff => write_vram(gb, addr, value),
        0xa000...0xbfff => write_mbc_ram(gb, addr, value),
        0xc000...0xcfff => write_ram(gb, addr, value),
        0xd000...0xdfff => write_banked_ram(gb, addr, value),
        // TODO: clean up
        0xe000...0xfdff => write_ram(gb, addr - 0x2000, value),
        0xfe00...0xfe9f => write_oam(gb, addr, value),
        0xfea0...0xfeff => write_not_usable(gb, addr, value),
        0xff00...0xff7f => write_io_registers(gb, addr, value),
        0xff80...0xfffe => write_hram(gb, addr, value),
        0xffff => write_ie(gb, value),
    };
}

fn write_mbc_rom(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
    // @panic("unimplemented");
}

fn write_vram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.vram[addr - VRAM_START] = value;
}

fn write_mbc_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
    // @panic("unimplemented");
}

fn write_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.ram[addr - RAM_START] = value;
}

fn write_banked_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.ram[addr - RAM_START] = value;
}

fn write_oam(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.oam[addr - OAM_START] = value;
}

fn write_not_usable(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
    // @panic("unimplemented");
}

fn write_io_registers(gb: *gameboy.State, addr: Addr, value: u8) void {
    switch (addr) {
        0xff00 => gb.io_registers.joyp = @bitCast(@as(u2, @truncate(value >> 4))),
        0xff04 => gb.io_registers.div = 0,
        0xff05 => gb.io_registers.tima = value,
        0xff06 => gb.io_registers.tma = value,
        0xff07 => gb.io_registers.tac = @bitCast(value & 0b111),
        0xff0f => gb.io_registers.intf = @bitCast(value & 0b11111),
        0xff40 => gb.io_registers.lcdc = @bitCast(value),
        0xff41 => gb.io_registers.stat = @bitCast(value & 0x7f),
        0xff42 => gb.io_registers.scy = value,
        0xff43 => gb.io_registers.scx = value,
        0xff45 => gb.io_registers.lyc = value,
        0xff46 => {
            gb.io_registers.dma = value;
            // TODO: naive
            const start: Addr = @as(u16, value) << 8;
            for (start..start + 0xa0) |a| {
                const byte = readByte(gb, @intCast(a));
                gb.oam[a - start] = byte;
            }
        },
        0xff47 => gb.io_registers.bgp = @bitCast(value),
        0xff48 => gb.io_registers.obp0 = @bitCast(value),
        0xff49 => gb.io_registers.obp1 = @bitCast(value),
        0xff50 => {
            gb.io_registers.boot_rom_finished =
                gb.io_registers.boot_rom_finished or value != 0;
        },
        else => {},
    }
}

fn write_hram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.hram[addr - HRAM_START] = value;
}

fn write_ie(gb: *gameboy.State, value: u8) void {
    gb.io_registers.ie = @bitCast(value);
}
