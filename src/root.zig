const std = @import("std");
const allocator = std.heap.wasm_allocator;

const gameboy = @import("gb.zig");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

export fn init() ?*gameboy.State {
    const gb = allocator.create(gameboy.State) catch return null;
    gb.* = gameboy.State.init(allocator) catch return null;
    return gb;
}

export fn execute(gb: *gameboy.State) void {
    cpu.execute(gb);
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
