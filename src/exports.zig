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
    gb.memory.rom = ptr[0..len];
}

/// Try to run for the given amount of `cycles`, returning the delta.
export fn stepCycles(gb: *gameboy.State, cycles: i32) i32 {
    const target_cycles = cycles;
    var consumed_cycles: i32 = 0;

    while (consumed_cycles < target_cycles) {
        const consumed = cpu.step(gb);
        consumed_cycles += consumed;
    }

    return target_cycles - consumed_cycles;
}

export fn pixels(gb: *gameboy.State) [*]ppu.Pixel {
    return gb.ppu.pixels;
}

export fn buttonPress(gb: *gameboy.State, button: joypad.Button) void {
    joypad.press(gb, button);
}

export fn buttonRelease(gb: *gameboy.State, button: joypad.Button) void {
    joypad.release(gb, button);
}

export fn readLeftAudioChannel(gb: *gameboy.State, ptr: [*]f32, len: u32) usize {
    return gb.apu.l_chan.read(ptr[0..len]);
}

export fn readRightAudioChannel(gb: *gameboy.State, ptr: [*]f32, len: u32) usize {
    return gb.apu.r_chan.read(ptr[0..len]);
}
