//! The main interface to the emulator.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

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

    pub fn reset(self: *@This(), allocator: mem.Allocator) void {
        self.* = @This(){
            .cpu = cpu.State.init(),
            .joypad = joypad.State.init(),
            .timer = timer.State.init(),
            .memory = self.memory.reset(allocator),
            .ppu = self.ppu.reset(),
            .apu = self.apu.reset(),
        };
    }

    /// Steps all components of the emulator once.
    pub fn tick(self: *@This()) void {
        if (self.timer.pending_cycles != 0) {
            ppu.step(self);
            apu.step(self);
            timer.step(self);
            self.timer.pending_cycles = 0;
        }

        const cycles = timer.T_CYCLES_PER_M_CYCLE * @as(u8, self.speedMultiplier());
        self.timer.pending_cycles += cycles;
        self.cpu.cycles_since_run += cycles;
    }

    /// Multiplier depending on if the CPU is in double speed mode.
    pub fn speedMultiplier(self: *@This()) u2 {
        return switch (self.memory.io.key1.speed) {
            .single => 1,
            .double => 2,
        };
    }
};

test "does not leak memory" {
    var gb = try State.init(testing.allocator);
    defer gb.deinit(testing.allocator);
}

test "does not leak memory on reset" {
    var gb = try State.init(testing.allocator);
    gb.reset(testing.allocator);
    defer gb.deinit(testing.allocator);
}
