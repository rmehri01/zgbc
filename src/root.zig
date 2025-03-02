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
}

export fn stepUntil(gb: *gameboy.State, pc: u16) void {
    while (gb.registers.named16.pc != pc) {
        cpu.step(gb);
    }
}

const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

var pixel_buf = [_]Pixel{.{ .r = 255, .g = 0, .b = 0, .a = 255 }} ** (144 * 160);

export fn pixels(gb: *gameboy.State) [*]Pixel {
    // TODO: return based on display state
    _ = gb; // autofix
    return &pixel_buf;
}
