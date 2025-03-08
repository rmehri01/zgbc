const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// Number of system clock cycles per memory cycle.
pub const T_CYCLES_PER_M_CYCLE = 4;

/// Execute a single step of the timer.
pub fn step(gb: *gameboy.State) void {
    const m_cycles = gb.pending_cycles / T_CYCLES_PER_M_CYCLE;
    gb.acc_clock += m_cycles;

    while (gb.acc_clock >= 4) : (gb.acc_clock -= 4) {
        gb.div_clock += 1;
        if (gb.div_clock == 16) {
            gb.io_registers.div +%= 1;
            gb.div_clock = 0;
        }

        if (gb.io_registers.tac.running) {
            gb.tima_clock += 1;
            const threshold: u8 = switch (gb.io_registers.tac.speed) {
                .hz4096 => 64,
                .hz262144 => 1,
                .hz65536 => 4,
                .hz16384 => 16,
            };

            if (gb.tima_clock >= threshold) {
                const value, const overflowed = @addWithOverflow(gb.io_registers.tima, 1);
                gb.io_registers.tima = value;

                if (overflowed == 1) {
                    gb.io_registers.tima = gb.io_registers.tma;
                    gb.io_registers.intf.timer = true;
                }

                gb.tima_clock = 0;
            }
        }
    }
}
