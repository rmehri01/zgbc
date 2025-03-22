//! Audio Processing Unit.

const std = @import("std");
const fifo = std.fifo;
const math = std.math;

const gameboy = @import("gb.zig");
const timer = @import("timer.zig");
const cpu = @import("cpu.zig");

/// Rate at which samples are consumed by the audio driver.
pub const SAMPLE_RATE = 65536;

/// The size of the audio sample buffer.
pub const SAMPLE_BUFFER_SIZE = 4096;

/// Tracks the internal state of the apu.
pub const State = struct {
    /// Used to generate clocks for other units such as length, envelope, and sweep.
    frame_sequencer: struct {
        /// When this clock overflows, increment step.
        clock: u13,
        /// Determines which of the other units to clock.
        step: u3,
    },
    /// Audio channel 1.
    ch1: struct {
        /// Whether the Digital to Analog Converter is enabled.
        dac_enabled: bool,
        /// How often the wave duty position is incremented.
        frequency: u11,
        /// Steps wave generation.
        frequency_timer: u14,
        /// Position in the waveform.
        position: u3,
        /// Shuts off the channel after a certain amount of time.
        length: struct {
            /// The time before the channel shuts off.
            timer: u7,
        },
        /// Current envelope state.
        envelope: Envelope,
        /// Current sweep state.
        sweep: struct {
            /// Whether the sweep is enabled.
            enabled: bool,
            /// The time before the sweep ticks.
            timer: u4,
        },
    },
    /// Audio channel 2.
    ch2: struct {
        /// Whether the Digital to Analog Converter is enabled.
        dac_enabled: bool,
        /// How often the wave duty position is incremented.
        frequency: u11,
        /// Steps wave generation.
        frequency_timer: u14,
        /// Position in the waveform.
        position: u3,
        /// Shuts off the channel after a certain amount of time.
        length: struct {
            /// The time before the channel shuts off.
            timer: u7,
        },
        /// Current envelope state.
        envelope: Envelope,
    },
    /// Audio channel 3.
    ch3: struct {
        /// Whether the Digital to Analog Converter is enabled.
        dac_enabled: bool,
        /// How often the wave pattern position is incremented.
        frequency: u11,
        /// Steps wave pattern.
        frequency_timer: u13,
        /// Position in the wave pattern ram.
        position: u5,
        /// Shuts off the channel after a certain amount of time.
        length: struct {
            /// The time before the channel shuts off.
            timer: u9,
        },
    },
    /// Audio channel 4.
    ch4: struct {
        /// Whether the Digital to Analog Converter is enabled.
        dac_enabled: bool,
        /// Linear feedback shift register.
        lfsr: u15,
        /// Steps noise pattern.
        frequency_timer: u14,
        /// Shuts off the channel after a certain amount of time.
        length: struct {
            /// The time before the channel shuts off.
            timer: u7,
        },
        /// Current envelope state.
        envelope: Envelope,
    },
    /// Left output audio channel.
    l_chan: OutputBuffer,
    /// Right output audio channel.
    r_chan: OutputBuffer,

    pub fn init() @This() {
        return @This(){
            .frame_sequencer = .{
                .clock = 0,
                .step = 0,
            },
            .ch1 = .{
                .dac_enabled = false,
                .frequency = 0,
                .frequency_timer = 0,
                .position = 0,
                .length = .{
                    .timer = 0,
                },
                .envelope = .{
                    .timer = 0,
                    .value = 0,
                },
                .sweep = .{
                    .enabled = false,
                    .timer = 0,
                },
            },
            .ch2 = .{
                .dac_enabled = false,
                .frequency = 0,
                .frequency_timer = 0,
                .position = 0,
                .length = .{
                    .timer = 0,
                },
                .envelope = .{
                    .timer = 0,
                    .value = 0,
                },
            },
            .ch3 = .{
                .dac_enabled = false,
                .frequency = 0,
                .frequency_timer = 0,
                .position = 0,
                .length = .{
                    .timer = 0,
                },
            },
            .ch4 = .{
                .dac_enabled = false,
                .lfsr = 0,
                .frequency_timer = 0,
                .length = .{
                    .timer = 0,
                },
                .envelope = .{
                    .timer = 0,
                    .value = 0,
                },
            },
            .l_chan = OutputBuffer.init(),
            .r_chan = OutputBuffer.init(),
        };
    }
};

/// Where the final audio samples are written out to.
pub const OutputBuffer = fifo.LinearFifo(f32, .{ .Static = SAMPLE_BUFFER_SIZE });

/// Length timer and duty cycle.
pub const LengthTimerDutyCycle = packed struct(u8) {
    /// Higher values mean shorter time before the channel is cut.
    initial_length_timer: u6,
    /// Controls the output waveform.
    duty_cycle: DutyCycle,
};

/// Percentage of time spent low vs high.
const DutyCycle = enum(u2) {
    eighth = 0b00,
    quarter = 0b01,
    half = 0b10,
    three_quarters = 0b11,
};

/// The mapping for a duty and position to an amplitude.
const WAVE_DUTY_TABLE = [4][8]u1{
    [_]u1{ 0, 0, 0, 0, 0, 0, 0, 1 },
    [_]u1{ 1, 0, 0, 0, 0, 0, 0, 1 },
    [_]u1{ 1, 0, 0, 0, 0, 1, 1, 1 },
    [_]u1{ 0, 1, 1, 1, 1, 1, 1, 1 },
};

/// Volume and envelope.
pub const VolumeEnvelope = packed struct(u8) {
    /// How often the channel's envelope will change, 0 will disable the envelope.
    pace: u3,
    /// Whether the volume is increasing or decreasing over time.
    envelope_direction: enum(u1) { decreasing = 0, increasing = 1 },
    /// How loud the channel initially is.
    initial_volume: u4,
};

/// Period high and control.
pub const PeriodHighControl = packed struct(u8) {
    /// The upper 3 bits of the period value.
    period: u3,
    _: u3 = math.maxInt(u3),
    /// Whether the length timer is enabled.
    length_enable: bool,
    /// Writing any value will trigger the channel.
    trigger: bool,
};

/// Internal state of an envelope.
pub const Envelope = struct {
    /// The number of ticks until value is changed.
    timer: u4,
    /// The value multiplier of the envelope.
    value: u4,
};

/// Execute a single step of the apu.
pub fn step(gb: *gameboy.State) void {
    if (!gb.memory.io.nr52.enable) return;

    for (0..gb.timer.pending_cycles) |_| {
        // step all channels
        stepSquareChannel(gb, .ch1);
        stepSquareChannel(gb, .ch2);
        stepWaveChannel(gb);
        stepNoiseChannel(gb);

        // generate clocks for length, envelope, and sweep
        const value, const overflowed = @addWithOverflow(gb.apu.frame_sequencer.clock, 1);
        gb.apu.frame_sequencer.clock = value;
        if (overflowed == 1) {
            const all_channels = .{ .ch1, .ch2, .ch3, .ch4 };
            switch (gb.apu.frame_sequencer.step) {
                0 => {
                    inline for (all_channels) |channel| {
                        stepLength(gb, channel);
                    }
                },
                1 => {},
                2 => {
                    inline for (all_channels) |channel| {
                        stepLength(gb, channel);
                    }
                    stepSweep(gb);
                },
                3 => {},
                4 => {
                    inline for (all_channels) |channel| {
                        stepLength(gb, channel);
                    }
                },
                5 => {},
                6 => {
                    inline for (all_channels) |channel| {
                        stepLength(gb, channel);
                    }
                    stepSweep(gb);
                },
                7 => {
                    inline for (.{ .ch1, .ch2, .ch4 }) |channel| {
                        stepEnvelope(gb, channel);
                    }
                },
            }

            gb.apu.frame_sequencer.step +%= 1;
        }

        // generate one sample every CLOCK_RATE / SAMPLE_RATE
        if (gb.apu.frame_sequencer.clock % (cpu.CLOCK_RATE / SAMPLE_RATE) == 0) {
            const l_volume =
                @as(f32, @floatFromInt(gb.memory.io.nr50.volume_left)) / math.maxInt(u3);
            const l_mixed =
                (getPannedAmplitude(gb, .ch1, .left) +
                    getPannedAmplitude(gb, .ch2, .left) +
                    getPannedAmplitude(gb, .ch3, .left) +
                    getPannedAmplitude(gb, .ch4, .left)) / 4;
            const l_output_raw = l_volume * l_mixed;
            const l_output = highPassFilter(gb, l_output_raw, .left);
            gb.apu.l_chan.writeItem(l_output) catch |err| switch (err) {
                error.OutOfMemory => {
                    // make space if the buffer is already full
                    gb.apu.l_chan.discard(1);
                    gb.apu.l_chan.writeItemAssumeCapacity(l_output);
                },
            };

            const r_volume =
                @as(f32, @floatFromInt(gb.memory.io.nr50.volume_right)) / math.maxInt(u3);
            const r_mixed =
                (getPannedAmplitude(gb, .ch1, .right) +
                    getPannedAmplitude(gb, .ch2, .right) +
                    getPannedAmplitude(gb, .ch3, .right) +
                    getPannedAmplitude(gb, .ch4, .right)) / 4;
            const r_output_raw = r_volume * r_mixed;
            const r_output = highPassFilter(gb, r_output_raw, .right);
            gb.apu.r_chan.writeItem(r_output) catch |err| switch (err) {
                error.OutOfMemory => {
                    // make space if the buffer is already full
                    gb.apu.r_chan.discard(1);
                    gb.apu.r_chan.writeItemAssumeCapacity(r_output);
                },
            };
        }
    }
}

const AnyChannel = enum { ch1, ch2, ch3, ch4 };

/// Get the amplitude for a channel and output channel after panning is applied.
fn getPannedAmplitude(
    gb: *gameboy.State,
    comptime channel: AnyChannel,
    comptime output: enum { left, right },
) f32 {
    const chan_panned =
        @field(
            gb.memory.io.nr51,
            std.fmt.comptimePrint(
                "{s}_{s}",
                .{ @tagName(channel), @tagName(output) },
            ),
        );

    return if (chan_panned)
        getAmplitude(gb, channel)
    else
        0;
}

/// Get the amplitude for a channel, converting the input range of 0 to 15
/// into -1 to 1 and outputting 0 if the dac is disabled.
fn getAmplitude(gb: *gameboy.State, comptime channel: AnyChannel) f32 {
    const chan_state = switch (channel) {
        .ch1 => &gb.apu.ch1,
        .ch2 => &gb.apu.ch2,
        .ch3 => &gb.apu.ch3,
        .ch4 => &gb.apu.ch4,
    };
    const chan_enabled = switch (channel) {
        .ch1 => gb.memory.io.nr52.ch1_on,
        .ch2 => gb.memory.io.nr52.ch2_on,
        .ch3 => gb.memory.io.nr52.ch3_on,
        .ch4 => gb.memory.io.nr52.ch4_on,
    };

    const dac_input = switch (channel) {
        .ch1 => WAVE_DUTY_TABLE[@intFromEnum(gb.memory.io.nr11.duty_cycle)][chan_state.position] *
            chan_state.envelope.value,
        .ch2 => WAVE_DUTY_TABLE[@intFromEnum(gb.memory.io.nr21.duty_cycle)][chan_state.position] *
            chan_state.envelope.value,
        .ch3 => value: {
            const byte = gb.memory.io.wave_pattern_ram[chan_state.position / 2];
            const value = switch (@as(u1, @intCast(chan_state.position % 2))) {
                0 => byte.upper,
                1 => byte.lower,
            };

            break :value switch (gb.memory.io.nr32) {
                .mute => 0,
                .full => value,
                .half => value / 2,
                .quarter => value / 4,
            };
        },
        .ch4 => (~chan_state.lfsr & 1) * chan_state.envelope.value,
    };

    return if (chan_enabled and chan_state.dac_enabled)
        (@as(f32, @floatFromInt(dac_input)) / 7.5) - 1.0
    else
        0;
}

/// Handles updating the state of channels 1 and 2 on every T-cycle.
fn stepSquareChannel(gb: *gameboy.State, comptime channel: enum { ch1, ch2 }) void {
    const chan_state = switch (channel) {
        .ch1 => &gb.apu.ch1,
        .ch2 => &gb.apu.ch2,
    };

    // update duty based on duty cycle
    if (chan_state.frequency_timer == 0) {
        chan_state.frequency_timer = (@as(u14, 2048) - chan_state.frequency) * 4;
        chan_state.position +%= 1;
    }
    chan_state.frequency_timer -= 1;
}

/// Handles updating the state of channel 3 on every T-cycle.
fn stepWaveChannel(gb: *gameboy.State) void {
    if (gb.apu.ch3.frequency_timer == 0) {
        gb.apu.ch3.frequency_timer = (@as(u13, 2048) - gb.apu.ch3.frequency) * 2;
        gb.apu.ch3.position +%= 1;
    }
    gb.apu.ch3.frequency_timer -= 1;
}

/// Handles updating the state of channel 4 on every T-cycle.
fn stepNoiseChannel(gb: *gameboy.State) void {
    if (gb.apu.ch4.frequency_timer == 0) {
        const divider = if (gb.memory.io.nr43.clock_divider > 0)
            @as(u14, gb.memory.io.nr43.clock_divider) << 4
        else
            8;
        gb.apu.ch4.frequency_timer = divider << gb.memory.io.nr43.clock_shift;

        const xor_result = (gb.apu.ch4.lfsr & 0b01) ^ ((gb.apu.ch4.lfsr & 0b10) >> 1);
        gb.apu.ch4.lfsr = (xor_result << 14) | (gb.apu.ch4.lfsr >> 1);

        if (gb.memory.io.nr43.lfsr_width == .bit7) {
            gb.apu.ch4.lfsr &= ~(@as(u15, 1) << 6);
            gb.apu.ch4.lfsr |= xor_result << 6;
        }
    }
    gb.apu.ch4.frequency_timer -= 1;
}

/// Updates the length timer and checks if enough time has elapsed to
/// shut the channel off.
fn stepLength(gb: *gameboy.State, comptime channel: AnyChannel) void {
    const chan_state = switch (channel) {
        .ch1 => &gb.apu.ch1,
        .ch2 => &gb.apu.ch2,
        .ch3 => &gb.apu.ch3,
        .ch4 => &gb.apu.ch4,
    };
    const length_enable = switch (channel) {
        .ch1 => gb.memory.io.nr14.length_enable,
        .ch2 => gb.memory.io.nr24.length_enable,
        .ch3 => gb.memory.io.nr34.length_enable,
        .ch4 => gb.memory.io.nr44.length_enable,
    };
    const chan_enabled = switch (channel) {
        .ch1 => &gb.memory.io.nr52.ch1_on,
        .ch2 => &gb.memory.io.nr52.ch2_on,
        .ch3 => &gb.memory.io.nr52.ch3_on,
        .ch4 => &gb.memory.io.nr52.ch4_on,
    };

    if (length_enable) {
        chan_state.length.timer -|= 1;

        if (chan_state.length.timer == 0) {
            chan_enabled.* = false;
        }
    }
}

/// Updates the envelope timer and the volume of the envelope according to it's direction.
fn stepEnvelope(gb: *gameboy.State, comptime channel: enum { ch1, ch2, ch4 }) void {
    const chan_state = switch (channel) {
        .ch1 => &gb.apu.ch1,
        .ch2 => &gb.apu.ch2,
        .ch4 => &gb.apu.ch4,
    };
    const envelope_reg = switch (channel) {
        .ch1 => &gb.memory.io.nr12,
        .ch2 => &gb.memory.io.nr22,
        .ch4 => &gb.memory.io.nr42,
    };

    if (envelope_reg.pace != 0) {
        if (chan_state.envelope.timer > 0) {
            chan_state.envelope.timer -= 1;
        }

        if (chan_state.envelope.timer == 0) {
            chan_state.envelope.timer = envelope_reg.pace;

            switch (envelope_reg.envelope_direction) {
                .decreasing => chan_state.envelope.value -|= 1,
                .increasing => chan_state.envelope.value +|= 1,
            }
        }
    }
}

/// Updates the sweep timer and updates the frequency of the channel.
fn stepSweep(gb: *gameboy.State) void {
    gb.apu.ch1.sweep.timer -|= 1;

    if (gb.apu.ch1.sweep.timer == 0) {
        gb.apu.ch1.sweep.timer = if (gb.memory.io.nr10.pace > 0)
            gb.memory.io.nr10.pace
        else
            8;

        if (gb.apu.ch1.sweep.enabled and gb.memory.io.nr10.pace > 0) {
            const new_frequency = calculateFrequency(gb);

            if (gb.memory.io.nr52.ch1_on and gb.memory.io.nr10.step > 0) {
                gb.apu.ch1.frequency = new_frequency;
                _ = calculateFrequency(gb);
            }
        }
    }
}

/// Calculate new frequency and perform overflow check.
pub fn calculateFrequency(gb: *gameboy.State) u11 {
    const delta = gb.apu.ch1.frequency >> gb.memory.io.nr10.pace;
    const new_value, const overflowed = switch (gb.memory.io.nr10.direction) {
        .increasing => @addWithOverflow(gb.apu.ch1.frequency, delta),
        .decreasing => @subWithOverflow(gb.apu.ch1.frequency, delta),
    };

    if (overflowed == 1) {
        gb.memory.io.nr52.ch1_on = false;
    }

    return new_value;
}

/// Combines the hi and lo parts of the period into one value.
pub fn frequency(gb: *gameboy.State, comptime channel: enum { ch1, ch2, ch3 }) u11 {
    const hi, const lo = switch (channel) {
        .ch1 => .{ gb.memory.io.nr14.period, gb.memory.io.nr13 },
        .ch2 => .{ gb.memory.io.nr24.period, gb.memory.io.nr23 },
        .ch3 => .{ gb.memory.io.nr34.period, gb.memory.io.nr33 },
    };

    return @as(u11, hi) << 8 | lo;
}

var leftCapacitor: f32 = 0.0;
var rightCapacitor: f32 = 0.0;

/// Removes constant biases over time.
fn highPassFilter(gb: *gameboy.State, in: f32, comptime output: enum { left, right }) f32 {
    var out: f32 = 0.0;
    const capacitor = switch (output) {
        .left => &leftCapacitor,
        .right => &rightCapacitor,
    };

    if (gb.apu.ch1.dac_enabled or
        gb.apu.ch2.dac_enabled or
        gb.apu.ch3.dac_enabled or
        gb.apu.ch4.dac_enabled)
    {
        out = in - capacitor.*;
        capacitor.* = in - out * math.pow(f32, 0.998943, cpu.CLOCK_RATE / SAMPLE_RATE);
    }

    return out;
}
