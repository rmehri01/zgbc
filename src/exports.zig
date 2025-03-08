const std = @import("std");
const allocator = std.heap.wasm_allocator;

const zgbc = @import("root.zig");
const cpu = zgbc.cpu;
const gameboy = zgbc.gameboy;
const ppu = zgbc.ppu;
const joypad = zgbc.joypad;

export fn allocUint8Array(len: u32) [*]const u8 {
    const slice = allocator.alloc(u8, len) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

export fn init() ?*gameboy.State {
    const gb = allocator.create(gameboy.State) catch return null;
    gb.* = gameboy.State.init(allocator) catch return null;
    return gb;
}

export fn deinit(gb: *gameboy.State) void {
    gb.deinit(allocator);
}

export fn loadROM(gb: *gameboy.State, ptr: [*]u8, len: u32) void {
    // TODO: read header? mbc type?
    gb.rom = ptr[0..len];
}

export fn step(gb: *gameboy.State) void {
    cpu.step(gb);
}

export fn pixels(gb: *gameboy.State) [*]ppu.Pixel {
    return gb.pixels;
}

export fn buttonPress(gb: *gameboy.State, button: joypad.Button) void {
    joypad.press(gb, button);
}

export fn buttonRelease(gb: *gameboy.State, button: joypad.Button) void {
    joypad.release(gb, button);
}
