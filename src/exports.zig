const std = @import("std");
const allocator = std.heap.wasm_allocator;

const zgbc = @import("root.zig");
const cpu = zgbc.cpu;
const gameboy = zgbc.gameboy;
const memory = zgbc.memory;
const ppu = zgbc.ppu;

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
    gb.rom = ptr[0..len];
}

export fn step(gb: *gameboy.State) void {
    cpu.step(gb);
    // TODO: this should be inside tick
    ppu.step(gb);
    gb.pending_cycles = 0;

    if (gb.ime) {
        if (gb.io_registers.ie.v_blank and gb.io_registers.intf.v_blank) {
            gb.io_registers.intf.v_blank = false;
            cpu.rst(gb, 8);
        }
    }

    ppu.step(gb);
    gb.pending_cycles = 0;
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
