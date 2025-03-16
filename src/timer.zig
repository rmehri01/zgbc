//! System timer and clock logic.

const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// Number of system clock cycles per memory cycle.
pub const T_CYCLES_PER_M_CYCLE = 4;

/// Tracks the internal state of the timer.
pub const State = struct {
    /// The number of t-cycles that are pending.
    pending_cycles: u8,
    /// Accumulator for the clock state that feeds into div and tima.
    acc_clock: u8,
    /// The clock used to increment the div io register.
    div_clock: u8,
    /// The clock used to increment the tima io register.
    tima_clock: u8,

    pub fn init() @This() {
        return @This(){
            .pending_cycles = 0,
            .acc_clock = 0,
            .div_clock = 0,
            .tima_clock = 0,
        };
    }
};

/// Execute a single step of the timer.
pub fn step(gb: *gameboy.State) void {
    const m_cycles = gb.timer.pending_cycles / T_CYCLES_PER_M_CYCLE;
    gb.timer.acc_clock += m_cycles;

    while (gb.timer.acc_clock >= 4) : (gb.timer.acc_clock -= 4) {
        gb.timer.div_clock += 1;
        if (gb.timer.div_clock == 16) {
            gb.memory.io.div +%= 1;
            gb.timer.div_clock = 0;
        }

        if (gb.memory.io.tac.running) {
            gb.timer.tima_clock += 1;
            const threshold: u8 = switch (gb.memory.io.tac.speed) {
                .hz4096 => 64,
                .hz262144 => 1,
                .hz65536 => 4,
                .hz16384 => 16,
            };

            if (gb.timer.tima_clock >= threshold) {
                const value, const overflowed = @addWithOverflow(gb.memory.io.tima, 1);
                gb.memory.io.tima = value;

                if (overflowed == 1) {
                    gb.memory.io.tima = gb.memory.io.tma;
                    gb.memory.io.intf.timer = true;
                }

                gb.timer.tima_clock = 0;
            }
        }
    }
}
