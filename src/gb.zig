//! The main interface to the emulator.

const std = @import("std");
const mem = std.mem;

const apu = @import("apu.zig");
const cpu = @import("cpu.zig");
const joypad = @import("joypad.zig");
const memory = @import("memory.zig");
const ppu = @import("ppu.zig");
const timer = @import("timer.zig");

/// The main state of the gameboy emulator.
pub const State = struct {
    cpu: cpu.State,
    joypad: joypad.State,
    timer: timer.State,
    memory: memory.State,
    ppu: ppu.State,
    apu: apu.State,

    pub fn tick(self: *@This()) void {
        // TODO: naive
        self.timer.pending_cycles += timer.T_CYCLES_PER_M_CYCLE;
    }

    pub fn init(allocator: mem.Allocator) !@This() {
        return @This(){
            .cpu = cpu.State.init(),
            .joypad = joypad.State.init(),
            .timer = timer.State.init(),
            .memory = try memory.State.init(allocator),
            .ppu = try ppu.State.init(allocator),
            .apu = apu.State.init(),
        };
    }

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        self.memory.deinit(allocator);
        self.ppu.deinit(allocator);
    }
};
