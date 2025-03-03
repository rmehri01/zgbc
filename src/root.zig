const std = @import("std");
const allocator = std.heap.wasm_allocator;

const cpu = @import("cpu.zig");
const gameboy = @import("gb.zig");
const memory = @import("memory.zig");
const ppu = @import("ppu.zig");

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

export fn loadROM(gb: *gameboy.State, ptr: [*]u8, len: u32) void {
    gb.rom = ptr[0..len];
}

export fn step(gb: *gameboy.State) void {
    cpu.step(gb);
    // TODO: this should be inside tick
    ppu.step(gb);
    gb.pending_cycles = 0;
}

export fn stepUntil(gb: *gameboy.State, pc: u16) void {
    while (gb.registers.named16.pc != pc) {
        cpu.step(gb);
        // TODO: this should be inside tick
        ppu.step(gb);
        gb.pending_cycles = 0;
    }
}

export fn pixels(gb: *gameboy.State) [*]ppu.Pixel {
    return gb.pixels;
}

export fn buttonPress(gb: *gameboy.State, button: gameboy.Button) void {
    switch (button) {
        .select, .up => gb.io_registers.joyp.select_up = 0,
        .start, .down => gb.io_registers.joyp.start_down = 0,
        .b, .left => gb.io_registers.joyp.b_left = 0,
        .a, .right => gb.io_registers.joyp.a_right = 0,
    }
}

export fn buttonRelease(gb: *gameboy.State, button: gameboy.Button) void {
    switch (button) {
        .select, .up => gb.io_registers.joyp.select_up = 1,
        .start, .down => gb.io_registers.joyp.start_down = 1,
        .b, .left => gb.io_registers.joyp.b_left = 1,
        .a, .right => gb.io_registers.joyp.a_right = 1,
    }
}
