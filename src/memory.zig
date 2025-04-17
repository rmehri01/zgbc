//! Memory interface for ROM, RAM, and memory mapped I/O.

const std = @import("std");
const testing = std.testing;
const math = std.math;
const mem = std.mem;

const apu = @import("apu.zig");
const gameboy = @import("gb.zig");
const ppu = @import("ppu.zig");
const rom = @import("rom.zig");

/// 16-bit address to index ROM, RAM, and I/O.
pub const Addr = u16;

pub const MBC_ROM_START = 0x4000;
pub const VRAM_START = 0x8000;
pub const TILE_BLOCK0_START = 0x8000;
pub const TILE_BLOCK1_START = 0x8800;
pub const TILE_BLOCK2_START = 0x9000;
pub const TILE_MAP0_START = 0x9800;
pub const TILE_MAP1_START = 0x9c00;
pub const MBC_RAM_START = 0xa000;
pub const RAM_START = 0xc000;
pub const BANKED_RAM_START = 0xd000;
pub const OAM_START = 0xfe00;
pub const HRAM_START = 0xff80;

const boot_rom = @embedFile("boot/cgb.bin");

/// Tracks the internal state of memory.
pub const State = struct {
    /// The boot ROM to use when starting up.
    boot_rom: []const u8,
    /// The cartridge that is currently loaded.
    rom: ?rom.State,
    /// Video RAM.
    vram: *[0x4000]u8,
    /// Work RAM.
    ram: *[0x8000]u8,
    /// Object attribute memory.
    oam: *[0xa0]u8,
    /// High RAM.
    hram: *[0x7f]u8,
    /// Memory mapped I/O registers.
    io: struct {
        /// Joypad as a 2x4 matrix with two selectors into the `button_state`.
        joyp: packed struct(u2) {
            /// If 0, the buttons SsBA can be read from the lower nibble.
            select_d_pad: u1,
            /// If 0, the directional keys can be read from the lower nibble.
            select_buttons: u1,
        },
        /// Divider register.
        div: u8,
        /// Timer counter.
        tima: u8,
        /// Timer modulo.
        tma: u8,
        /// Timer control.
        tac: packed struct(u8) {
            speed: enum(u2) {
                hz4096 = 0b00,
                hz262144 = 0b01,
                hz65536 = 0b10,
                hz16384 = 0b11,
            },
            running: bool,
            _: u5 = math.maxInt(u5),
        },
        /// Interrupt flag, indicates whether the corresponding handler is being requested.
        intf: packed struct(u8) {
            v_blank: bool,
            lcd: bool,
            timer: bool,
            serial: bool,
            joypad: bool,
            _: u3 = math.maxInt(u3),
        },
        /// Channel 1 sweep.
        nr10: packed struct(u8) {
            /// Used to compute the new period on each iteration.
            step: u3,
            /// Whether the period is increasing or decreasing (addition or subtraction).
            direction: enum(u1) { increasing = 0, decreasing = 1 },
            /// How often sweep iterations happen in units of 128Hz ticks.
            pace: u3,
            _: u1 = 1,
        },
        /// Channel 1 length timer and duty cycle.
        nr11: apu.LengthTimerDutyCycle,
        /// Channel 1 volume and envelope.
        nr12: apu.VolumeEnvelope,
        /// Channel 1 period low.
        nr13: u8,
        /// Channel 1 period high and control.
        nr14: apu.PeriodHighControl,
        /// Channel 2 length timer and duty cycle.
        nr21: apu.LengthTimerDutyCycle,
        /// Channel 2 volume and envelope.
        nr22: apu.VolumeEnvelope,
        /// Channel 2 period low.
        nr23: u8,
        /// Channel 2 period high and control.
        nr24: apu.PeriodHighControl,
        /// Channel 3 initial length timer.
        nr31: u8,
        /// Channel 3 output level.
        nr32: enum(u2) {
            mute = 0b00,
            full = 0b01,
            half = 0b10,
            quarter = 0b11,
        },
        /// Channel 3 period low.
        nr33: u8,
        /// Channel 3 period high and control.
        nr34: apu.PeriodHighControl,
        /// Channel 4 initial length timer.
        nr41: u6,
        /// Channel 4 volume and envelope.
        nr42: apu.VolumeEnvelope,
        /// Channel 4 frequency and randomness.
        nr43: packed struct(u8) {
            clock_divider: u3,
            lfsr_width: enum(u1) { bit15 = 0, bit7 = 1 },
            clock_shift: u4,
        },
        /// Channel 4 control.
        nr44: packed struct(u8) {
            _: u6 = math.maxInt(u6),
            /// Whether the length timer is enabled.
            length_enable: bool,
            /// Writing any value will trigger the channel.
            trigger: bool,
        },
        /// Master volume and VIN panning.
        nr50: packed struct(u8) {
            volume_right: u3,
            vin_right: bool,
            volume_left: u3,
            vin_left: bool,
        },
        /// Sound panning.
        nr51: packed struct(u8) {
            ch1_right: bool,
            ch2_right: bool,
            ch3_right: bool,
            ch4_right: bool,
            ch1_left: bool,
            ch2_left: bool,
            ch3_left: bool,
            ch4_left: bool,
        },
        /// Audio master control.
        nr52: packed struct(u8) {
            /// Whether channel 1 is active.
            ch1_on: bool,
            /// Whether channel 2 is active.
            ch2_on: bool,
            /// Whether channel 3 is active.
            ch3_on: bool,
            /// Whether channel 4 is active.
            ch4_on: bool,
            _: u3 = math.maxInt(u3),
            /// Whether the apu is powered on at all.
            /// Turning this off will clear all APU registers and make them read-only.
            enable: bool,
        },
        /// Wave pattern RAM.
        wave_pattern_ram: [16]packed struct(u8) { lower: u4, upper: u4 },
        /// LCD control register.
        lcdc: packed struct(u8) {
            /// (DMG only) When cleared, the background and window are blank.
            /// (CGB only) When cleared, the background and window lose priority.
            bg_window_enable_priority: bool,
            /// Whether objects are displayed or not.
            obj_enable: bool,
            /// Controls the size of objects (1 or 2 tiles vertically).
            obj_size: enum(u1) {
                bit8 = 0,
                bit16 = 1,
            },
            /// If the bit is clear, the background uses tilemap 0x9800, otherwise
            /// tilemap 0x9c00.
            bg_tile_map_area: u1,
            /// If the bit is clear, the background and window use the 0x8800 method,
            /// otherwise they use the 0x8000 method.
            bg_window_tile_data_area: enum(u1) { signed = 0, unsigned = 1 },
            /// Whether the window is displayed or not.
            window_enable: bool,
            /// If the bit is clear, the window uses tilemap 0x9800, otherwise
            /// tilemap 0x9c00.
            window_tile_map_area: u1,
            /// Whether the LCD is on and the PPU is active.
            lcd_enable: bool,
        },
        /// LCD status
        stat: packed struct(u8) {
            /// The current rendering mode the ppu is in.
            mode: ppu.Mode,
            /// Set when `ly` contains the same value as `lyc`.
            lyc_eq: bool,
            /// If set, selects the h_blank (mode 0) condition for the STAT interrupt.
            h_blank_int_select: bool,
            /// If set, selects the v_blank (mode 1) condition for the STAT interrupt.
            v_blank_int_select: bool,
            /// If set, selects the oam_scan (mode 2) condition for the STAT interrupt.
            oam_scan_int_select: bool,
            /// If set, selects the lyc condition for the STAT interrupt.
            lyc_int_select: bool,
            _: u1 = 1,
        },
        /// Background viewport Y position.
        scy: u8,
        /// Background viewport X position.
        scx: u8,
        /// LCD Y coordinate, the current line that is being drawn in the ppu.
        ly: u8,
        /// LY compare, when enabled in `stat` and is equal to `ly` a STAT interrupt is requested.
        lyc: u8,
        /// OAM DMA source address and start.
        dma: u8,
        /// (DMG only) Background palette data.
        bgp: packed struct(u8) {
            id0: u2,
            id1: u2,
            id2: u2,
            id3: u2,
        },
        /// (DMG only) Object palette data 0.
        obp0: ppu.ObjectPalette,
        /// (DMG only) Object palette data 1.
        obp1: ppu.ObjectPalette,
        /// Window Y position.
        wy: u8,
        /// Window X position plus 7.
        wx: u8,
        /// (CGB only) CPU mode select.
        key0: enum(u1) { cgb = 0, dmg = 1 },
        /// (CGB only) Prepare speed switch.
        key1: packed struct(u8) {
            /// Prepared to switch on the next `stop` instruction.
            armed: bool,
            _: u6 = math.maxInt(u6),
            /// The current CPU speed of the gameboy.
            speed: enum(u1) { single = 0, double = 1 },
        },
        /// (CGB only) VRAM bank.
        vbk: u1,
        /// Set to non-zero to disable boot ROM, cannot be unset.
        boot_rom_finished: bool,
        /// (CGB only) VRAM DMA source, high.
        hdma1: u8,
        /// (CGB only) VRAM DMA source, low.
        hdma2: u8,
        /// (CGB only) VRAM DMA destination, high.
        hdma3: u8,
        /// (CGB only) VRAM DMA destination, low.
        hdma4: u8,
        /// (CGB only) VRAM DMA length/mode/start.
        hdma5: packed struct(u8) {
            /// The transfer length divided by 0x10 and minus 1.
            length: u7,
            mode: enum(u1) {
                /// All data transferred at once.
                general = 0,
                /// Transfers 0x10 bytes of data during each h_blank.
                h_blank = 1,
            },
        },
        /// (CGB only) Background color palette specification/index.
        bcps_bgpi: ppu.ColorPaletteIndex,
        /// (CGB only) Object color palette specification/index.
        ocps_obpi: ppu.ColorPaletteIndex,
        /// (CGB only) Object priority mode.
        opri: enum(u1) { cgb = 0, dmg = 1 },
        /// (CGB only) WRAM bank.
        svbk: u3,
        /// Interrupt enable, controls whether the corresponding handler may be called.
        /// This isn't actually part of the io register range but conceptually it is.
        ie: packed struct(u8) {
            v_blank: bool,
            lcd: bool,
            timer: bool,
            serial: bool,
            joypad: bool,
            _: u3 = 0,
        },
    },

    pub fn init(allocator: mem.Allocator) !@This() {
        const vram = try allocator.create([0x4000]u8);
        const ram = try allocator.create([0x8000]u8);
        const oam = try allocator.create([0xa0]u8);
        const hram = try allocator.create([0x7f]u8);

        return @This().initWithMem(vram, ram, oam, hram);
    }

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        if (self.rom) |r| {
            r.deinit(allocator);
        }

        allocator.destroy(self.vram);
        allocator.destroy(self.ram);
        allocator.destroy(self.oam);
        allocator.destroy(self.hram);
    }

    pub fn reset(self: @This(), allocator: mem.Allocator) @This() {
        if (self.rom) |r| {
            r.deinit(allocator);
        }

        @memset(self.vram, 0);
        @memset(self.ram, 0);
        @memset(self.oam, 0);
        @memset(self.hram, 0);

        return @This().initWithMem(self.vram, self.ram, self.oam, self.hram);
    }

    fn initWithMem(
        vram: *[0x4000]u8,
        ram: *[0x8000]u8,
        oam: *[0xa0]u8,
        hram: *[0x7f]u8,
    ) @This() {
        return @This(){
            .boot_rom = boot_rom,
            .rom = null,
            .vram = vram,
            .ram = ram,
            .oam = oam,
            .hram = hram,
            .io = .{
                .joyp = .{
                    .select_d_pad = 1,
                    .select_buttons = 1,
                },
                .div = 0,
                .tima = 0,
                .tma = 0,
                .tac = .{
                    .speed = .hz4096,
                    .running = false,
                },
                .intf = .{
                    .v_blank = false,
                    .lcd = false,
                    .timer = false,
                    .serial = false,
                    .joypad = false,
                },
                .nr10 = .{
                    .step = 0,
                    .direction = .increasing,
                    .pace = 0,
                },
                .nr11 = .{
                    .initial_length_timer = 0,
                    .duty_cycle = .eighth,
                },
                .nr12 = .{
                    .pace = 0,
                    .envelope_direction = .decreasing,
                    .initial_volume = 0,
                },
                .nr13 = 0,
                .nr14 = .{
                    .period = 0,
                    .length_enable = false,
                    .trigger = false,
                },
                .nr21 = .{
                    .initial_length_timer = 0,
                    .duty_cycle = .eighth,
                },
                .nr22 = .{
                    .pace = 0,
                    .envelope_direction = .decreasing,
                    .initial_volume = 0,
                },
                .nr23 = 0,
                .nr24 = .{
                    .period = 0,
                    .length_enable = false,
                    .trigger = false,
                },
                .nr31 = 0,
                .nr32 = .mute,
                .nr33 = 0,
                .nr34 = .{
                    .period = 0,
                    .length_enable = false,
                    .trigger = false,
                },
                .nr41 = 0,
                .nr42 = .{
                    .pace = 0,
                    .envelope_direction = .decreasing,
                    .initial_volume = 0,
                },
                .nr43 = .{
                    .clock_divider = 0,
                    .lfsr_width = .bit15,
                    .clock_shift = 0,
                },
                .nr44 = .{
                    .length_enable = false,
                    .trigger = false,
                },
                .nr50 = .{
                    .volume_right = 0,
                    .vin_right = false,
                    .volume_left = 0,
                    .vin_left = false,
                },
                .nr51 = .{
                    .ch1_right = false,
                    .ch2_right = false,
                    .ch3_right = false,
                    .ch4_right = false,
                    .ch1_left = false,
                    .ch2_left = false,
                    .ch3_left = false,
                    .ch4_left = false,
                },
                .nr52 = .{
                    .ch1_on = false,
                    .ch2_on = false,
                    .ch3_on = false,
                    .ch4_on = false,
                    .enable = false,
                },
                .wave_pattern_ram = @bitCast([_]u8{ 0x00, 0xff } ** 8),
                .lcdc = .{
                    .bg_window_enable_priority = false,
                    .obj_enable = false,
                    .obj_size = .bit8,
                    .bg_tile_map_area = 0,
                    .bg_window_tile_data_area = .signed,
                    .window_enable = false,
                    .window_tile_map_area = 0,
                    .lcd_enable = false,
                },
                .stat = .{
                    .mode = .oam_scan,
                    .lyc_eq = false,
                    .h_blank_int_select = false,
                    .v_blank_int_select = false,
                    .oam_scan_int_select = false,
                    .lyc_int_select = false,
                },
                .scy = 0,
                .scx = 0,
                .ly = 0,
                .lyc = 0,
                .bgp = .{
                    .id0 = 0,
                    .id1 = 0,
                    .id2 = 0,
                    .id3 = 0,
                },
                .dma = 0,
                .obp0 = .{
                    .id1 = 0,
                    .id2 = 0,
                    .id3 = 0,
                },
                .obp1 = .{
                    .id1 = 0,
                    .id2 = 0,
                    .id3 = 0,
                },
                .wy = 0,
                .wx = 0,
                .key0 = .cgb,
                .key1 = .{
                    .speed = .single,
                    .armed = false,
                },
                .vbk = 0,
                .boot_rom_finished = false,
                .hdma1 = 0,
                .hdma2 = 0,
                .hdma3 = 0,
                .hdma4 = 0,
                .hdma5 = .{
                    .length = math.maxInt(u7),
                    .mode = .h_blank,
                },
                .svbk = 1,
                .bcps_bgpi = .{
                    .addr = 0,
                    .auto_increment = false,
                },
                .ocps_obpi = .{
                    .addr = 0,
                    .auto_increment = false,
                },
                .opri = .cgb,
                .ie = .{
                    .v_blank = false,
                    .lcd = false,
                    .timer = false,
                    .serial = false,
                    .joypad = false,
                },
            },
        };
    }
};

/// Reads a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn readByte(gb: *gameboy.State, addr: Addr) u8 {
    return switch (addr) {
        0x0000...0x3fff => read_rom(gb, addr),
        0x4000...0x7fff => read_mbc_rom(gb, addr),
        0x8000...0x9fff => read_vram(gb, addr, gb.memory.io.vbk),
        0xa000...0xbfff => read_mbc_ram(gb, addr),
        0xc000...0xcfff => read_ram(gb, addr),
        0xd000...0xdfff => read_banked_ram(gb, addr),
        0xe000...0xfdff => read_ram(gb, addr - 0x2000),
        0xfe00...0xfe9f => read_oam(gb, addr),
        0xfea0...0xfeff => read_not_usable(gb, addr),
        0xff00...0xff7f => read_io_registers(gb, addr),
        0xff80...0xfffe => read_hram(gb, addr),
        0xffff => read_ie(gb),
    };
}

fn read_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (!gb.memory.io.boot_rom_finished and
        (addr < 0x100 or (0x200 <= addr and addr < 0x900)))
    {
        return gb.memory.boot_rom[addr];
    }

    if (gb.memory.rom) |r| {
        return r.data[addr];
    }

    return 0xff;
}

fn read_mbc_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (gb.memory.rom) |r| {
        const bank = switch (r.mbc) {
            .rom_only => 1,
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |mbc1| mbc1.rom_bank,
            .mbc2, .mbc2_battery => |mbc2| mbc2.rom_bank,
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |mbc3| mbc3.rom_bank,
            .mbc5,
            .mbc5_ram,
            .mbc5_ram_battery,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            .mbc5_rumble_ram_battery,
            => |mbc5| mbc5.rom_bank,
        };
        return r.data[bank * @as(u32, 0x4000) + (addr - MBC_ROM_START)];
    }

    return 0xff;
}

pub fn read_vram(gb: *gameboy.State, addr: Addr, bank: u1) u8 {
    return gb.memory.vram[(addr - VRAM_START) + @as(u16, 0x2000) * bank];
}

fn read_mbc_ram(gb: *gameboy.State, addr: Addr) u8 {
    if (gb.memory.rom) |r| {
        const bank: u16 = switch (r.mbc) {
            .rom_only => 0,
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |mbc1| if (mbc1.mbc_ram_enable)
                mbc1.ram_bank
            else
                return 0xff,
            .mbc2, .mbc2_battery => |mbc2| if (mbc2.mbc_ram_enable)
                return mbc2.builtin_ram[(addr - MBC_RAM_START) & 0x1ff]
            else
                return 0xff,
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |mbc3| if (mbc3.mbc_ram_enable and mbc3.mode == .ram)
                mbc3.ram_bank
            else
                return 0xff,
            .mbc5,
            .mbc5_ram,
            .mbc5_ram_battery,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            .mbc5_rumble_ram_battery,
            => |mbc5| if (mbc5.mbc_ram_enable)
                mbc5.ram_bank
            else
                return 0xff,
        };

        if (r.num_ram_banks() == 0) {
            return 0xff;
        } else {
            return r.mbc_ram[bank * @as(u16, 0x2000) + (addr - MBC_RAM_START)];
        }
    }

    return 0xff;
}

fn read_ram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.ram[addr - RAM_START];
}

fn read_banked_ram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.ram[(addr - BANKED_RAM_START) + @as(u16, 0x1000) * gb.memory.io.svbk];
}

fn read_oam(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.oam[addr - OAM_START];
}

fn read_not_usable(gb: *gameboy.State, addr: Addr) u8 {
    _ = gb; // autofix
    _ = addr; // autofix
    // TODO: oam corruption
    return 0;
}

fn read_io_registers(gb: *gameboy.State, addr: Addr) u8 {
    return switch (addr) {
        0xff00 => value: {
            const nibble = if (gb.memory.io.joyp.select_d_pad == 0)
                gb.joypad.button_state.nibbles.d_pad
            else if (gb.memory.io.joyp.select_buttons == 0)
                gb.joypad.button_state.nibbles.buttons
            else
                0xf;
            break :value @as(u8, 0b11) << 6 |
                @as(u8, @as(u2, @bitCast(gb.memory.io.joyp))) << 4 |
                nibble;
        },
        0xff04 => gb.memory.io.div,
        0xff05 => gb.memory.io.tima,
        0xff06 => gb.memory.io.tma,
        0xff07 => @bitCast(gb.memory.io.tac),
        0xff0f => @bitCast(gb.memory.io.intf),
        0xff10 => @bitCast(gb.memory.io.nr10),
        0xff11 => @as(u8, @bitCast(gb.memory.io.nr11)) | 0x3f,
        0xff12 => @bitCast(gb.memory.io.nr12),
        0xff13 => 0xff,
        0xff14 => @as(u8, @bitCast(gb.memory.io.nr14)) | 0xbf,
        0xff16 => @as(u8, @bitCast(gb.memory.io.nr21)) | 0x3f,
        0xff17 => @bitCast(gb.memory.io.nr22),
        0xff18 => 0xff,
        0xff19 => @as(u8, @bitCast(gb.memory.io.nr24)) | 0xbf,
        0xff1a => @as(u8, @intFromBool(gb.apu.ch3.dac_enabled)) << 7 | 0x7f,
        0xff1b => 0xff,
        0xff1c => 0x9f | @as(u8, @intFromEnum(gb.memory.io.nr32)) << 5,
        0xff1d => 0xff,
        0xff1e => @as(u8, @bitCast(gb.memory.io.nr34)) | 0xbf,
        0xff20 => 0xff,
        0xff21 => @bitCast(gb.memory.io.nr42),
        0xff22 => @bitCast(gb.memory.io.nr43),
        0xff23 => @as(u8, @bitCast(gb.memory.io.nr44)) | 0xbf,
        0xff24 => @bitCast(gb.memory.io.nr50),
        0xff25 => @bitCast(gb.memory.io.nr51),
        0xff26 => @bitCast(gb.memory.io.nr52),
        inline 0xff30...0xff3f => |a| value: {
            const idx: u4 = @truncate(a);
            break :value @bitCast(gb.memory.io.wave_pattern_ram[idx]);
        },
        0xff40 => @bitCast(gb.memory.io.lcdc),
        0xff41 => @bitCast(gb.memory.io.stat),
        0xff42 => gb.memory.io.scy,
        0xff43 => gb.memory.io.scx,
        0xff44 => gb.memory.io.ly,
        0xff45 => gb.memory.io.lyc,
        0xff46 => gb.memory.io.dma,
        0xff47 => @bitCast(gb.memory.io.bgp),
        0xff48 => @bitCast(gb.memory.io.obp0),
        0xff49 => @bitCast(gb.memory.io.obp1),
        0xff4a => gb.memory.io.wy,
        0xff4b => gb.memory.io.wx,
        0xff4c => 0xfb | (@as(u8, @intFromEnum(gb.memory.io.key0)) << 2),
        0xff4d => @bitCast(gb.memory.io.key1),
        0xff4f => @as(u8, 0xfe) | gb.memory.io.vbk,
        0xff50 => @as(u8, 0xfe) | @intFromBool(gb.memory.io.boot_rom_finished),
        0xff55 => @bitCast(gb.memory.io.hdma5),
        0xff68 => @bitCast(gb.memory.io.bcps_bgpi),
        0xff69 => gb.ppu.bg_color_ram[gb.memory.io.bcps_bgpi.addr],
        0xff6a => @bitCast(gb.memory.io.ocps_obpi),
        0xff6b => gb.ppu.obj_color_ram[gb.memory.io.ocps_obpi.addr],
        0xff6c => @as(u8, 0xfe) | @intFromEnum(gb.memory.io.opri),
        0xff70 => @as(u8, 0xf8) | gb.memory.io.svbk,
        else => 0xff,
    };
}

fn read_hram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.hram[addr - HRAM_START];
}

fn read_ie(gb: *gameboy.State) u8 {
    return @bitCast(gb.memory.io.ie);
}

/// Writes a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn writeByte(gb: *gameboy.State, addr: Addr, value: u8) void {
    return switch (addr) {
        0x0000...0x7fff => write_mbc_rom(gb, addr, value),
        0x8000...0x9fff => write_vram(gb, addr, value),
        0xa000...0xbfff => write_mbc_ram(gb, addr, value),
        0xc000...0xcfff => write_ram(gb, addr, value),
        0xd000...0xdfff => write_banked_ram(gb, addr, value),
        0xe000...0xfdff => write_ram(gb, addr - 0x2000, value),
        0xfe00...0xfe9f => write_oam(gb, addr, value),
        0xfea0...0xfeff => write_not_usable(gb, addr, value),
        0xff00...0xff7f => write_io_registers(gb, addr, value),
        0xff80...0xfffe => write_hram(gb, addr, value),
        0xffff => write_ie(gb, value),
    };
}

fn write_mbc_rom(gb: *gameboy.State, addr: Addr, value: u8) void {
    if (gb.memory.rom) |*r| {
        switch (r.mbc) {
            .rom_only => {},
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |*mbc1| switch ((addr & 0xf000) >> 12) {
                0x0, 0x1 => mbc1.mbc_ram_enable = (value & 0x0f) == 0x0a,
                0x2, 0x3 => {
                    var lo: u5 = @intCast(value & 0x1f);
                    if (lo == 0) {
                        lo = 1;
                    }
                    lo &= @intCast(r.num_rom_banks() - 1);

                    mbc1.rom_bank = lo;
                },
                0x4, 0x5 => {
                    const ram_bank: u2 = @intCast(value & 0b11);
                    if (r.num_ram_banks() <= ram_bank) {
                        return;
                    }
                    mbc1.ram_bank = ram_bank;
                },
                6, 7 => {},
                else => unreachable,
            },
            .mbc2, .mbc2_battery => |*mbc2| if ((addr & 0x0100) != 0) {
                var lo: u4 = @intCast(value & 0x0f);
                if (lo == 0) {
                    lo = 1;
                }
                lo &= @intCast(r.num_rom_banks() - 1);

                mbc2.rom_bank = lo;
            } else {
                mbc2.mbc_ram_enable = (value & 0x0f) == 0x0a;
            },
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |*mbc3| switch ((addr & 0xf000) >> 12) {
                0x0, 0x1 => mbc3.mbc_ram_enable = (value & 0x0f) == 0x0a,
                0x2, 0x3 => {
                    var lo: u7 = @intCast(value & 0x7f);
                    if (lo == 0) {
                        lo = 1;
                    }
                    lo &= @intCast(r.num_rom_banks() - 1);

                    mbc3.rom_bank = lo;
                },
                0x4, 0x5 => if (value <= 0x07) {
                    mbc3.mode = .ram;

                    const ram_bank: u3 = @intCast(value);
                    if (r.num_ram_banks() <= ram_bank) {
                        return;
                    }
                    mbc3.ram_bank = ram_bank;
                } else if (value <= 0x0c) {
                    mbc3.mode = .rtc;
                },
                0x6, 0x7 => {},
                else => unreachable,
            },
            .mbc5,
            .mbc5_ram,
            .mbc5_ram_battery,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            .mbc5_rumble_ram_battery,
            => |*mbc5| switch ((addr & 0xf000) >> 12) {
                0x0, 0x1 => mbc5.mbc_ram_enable = (value & 0x0f) == 0x0a,
                0x2 => mbc5.rom_bank = (mbc5.rom_bank & 0x100) | value,
                0x3 => mbc5.rom_bank = (@as(u9, value) & 1) << 8 | (mbc5.rom_bank & 0xff),
                0x4, 0x5 => {
                    var ram_bank: u4 = @intCast(value & 0xf);

                    if (r.mbc == .mbc5_rumble or
                        r.mbc == .mbc5_rumble_ram or
                        r.mbc == .mbc5_rumble_ram_battery)
                    {
                        const rumble = (ram_bank & 0x08) != 0;
                        if (rumble != mbc5.rumble_active) {
                            mbc5.rumble_active = rumble;
                            if (rom.rumble_changed) |rumble_callback| {
                                rumble_callback(rumble);
                            }
                        }
                        ram_bank &= 0b111;
                    }

                    if (r.num_ram_banks() <= ram_bank) {
                        return;
                    }

                    mbc5.ram_bank = ram_bank;
                },
                0x6, 0x7 => {},
                else => unreachable,
            },
        }
    }
}

fn write_vram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.vram[
        (addr - VRAM_START) + @as(u16, 0x2000) * gb.memory.io.vbk
    ] = value;
}

fn write_mbc_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    if (gb.memory.rom) |*r| {
        const bank = switch (r.mbc) {
            .rom_only => 1,
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |mbc1| if (mbc1.mbc_ram_enable)
                mbc1.ram_bank
            else
                return,
            .mbc2, .mbc2_battery => |mbc2| if (mbc2.mbc_ram_enable) {
                mbc2.builtin_ram[(addr - MBC_RAM_START) & 0x1ff] = value;
                return;
            } else return,
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |mbc3| if (mbc3.mbc_ram_enable and mbc3.mode == .ram)
                mbc3.ram_bank
            else
                return,
            .mbc5,
            .mbc5_ram,
            .mbc5_ram_battery,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            .mbc5_rumble_ram_battery,
            => |mbc5| if (mbc5.mbc_ram_enable)
                mbc5.ram_bank
            else
                return,
        };

        if (r.num_ram_banks() == 0) {
            return;
        } else {
            r.mbc_ram[bank * @as(u16, 0x2000) + (addr - MBC_RAM_START)] = value;
        }
    }
}

fn write_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.ram[addr - RAM_START] = value;
}

fn write_banked_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.ram[(addr - BANKED_RAM_START) + @as(u16, 0x1000) * gb.memory.io.svbk] = value;
}

fn write_oam(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.oam[addr - OAM_START] = value;
}

fn write_not_usable(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
}

fn write_io_registers(gb: *gameboy.State, addr: Addr, value: u8) void {
    switch (addr) {
        0xff00 => gb.memory.io.joyp = @bitCast(@as(u2, @truncate(value >> 4))),
        0xff04 => gb.memory.io.div = 0,
        0xff05 => gb.memory.io.tima = value,
        0xff06 => gb.memory.io.tma = value,
        0xff07 => gb.memory.io.tac = @bitCast(0xf8 | value),
        0xff0f => gb.memory.io.intf = @bitCast(0xe0 | value),
        inline 0xff10...0xff25 => |a| {
            if (!gb.memory.io.nr52.enable) {
                return;
            }

            switch (a) {
                0xff10 => {
                    gb.memory.io.nr10 = @bitCast(0x80 | value);
                },
                0xff11 => {
                    gb.memory.io.nr11 = @bitCast(value);
                    gb.apu.ch1.length.timer = @as(u7, 64) - gb.memory.io.nr11.initial_length_timer;
                },
                0xff12 => {
                    gb.memory.io.nr12 = @bitCast(value);

                    gb.apu.ch1.dac_enabled = gb.memory.io.nr12.initial_volume != 0 or
                        gb.memory.io.nr12.envelope_direction != .decreasing;
                    if (!gb.apu.ch1.dac_enabled) {
                        gb.memory.io.nr52.ch1_on = false;
                    }
                },
                0xff13 => {
                    gb.memory.io.nr13 = value;
                },
                0xff14 => {
                    const apu_glitch = !gb.memory.io.nr14.length_enable and
                        (value & 0x40) != 0 and
                        gb.apu.frame_sequencer.step & 1 != 0 and
                        gb.apu.ch1.length.timer != 0;
                    gb.memory.io.nr14 = @bitCast(0b00111000 | value);

                    if (gb.memory.io.nr14.trigger and gb.apu.ch1.dac_enabled) {
                        gb.memory.io.nr14.trigger = false;

                        gb.apu.ch1.frequency = apu.frequency(gb, .ch1);

                        if (gb.apu.ch1.length.timer == 0) {
                            gb.apu.ch1.length.timer = 64;
                        }

                        gb.apu.ch1.envelope.timer = if (gb.memory.io.nr12.pace > 0)
                            gb.memory.io.nr12.pace
                        else
                            8;
                        gb.apu.ch1.envelope.value = gb.memory.io.nr12.initial_volume;

                        gb.apu.ch1.sweep.enabled =
                            gb.memory.io.nr10.pace > 0 or gb.memory.io.nr10.step > 0;
                        gb.apu.ch1.sweep.timer = if (gb.memory.io.nr10.pace > 0)
                            gb.memory.io.nr10.pace
                        else
                            8;
                        if (gb.memory.io.nr10.step > 0) {
                            _ = apu.calculateFrequency(gb);
                        }

                        gb.memory.io.nr52.ch1_on = true;
                    }

                    if (apu_glitch) {
                        apu.stepLength(gb, .ch1);
                    }
                },
                0xff16 => {
                    gb.memory.io.nr21 = @bitCast(value);
                    gb.apu.ch2.length.timer = @as(u7, 64) - gb.memory.io.nr21.initial_length_timer;
                },
                0xff17 => {
                    gb.memory.io.nr22 = @bitCast(value);

                    gb.apu.ch2.dac_enabled = gb.memory.io.nr22.initial_volume != 0 or
                        gb.memory.io.nr22.envelope_direction != .decreasing;
                    if (!gb.apu.ch2.dac_enabled) {
                        gb.memory.io.nr52.ch2_on = false;
                    }
                },
                0xff18 => {
                    gb.memory.io.nr23 = value;
                },
                0xff19 => {
                    gb.memory.io.nr24 = @bitCast(0b00111000 | value);

                    if (gb.memory.io.nr24.trigger and gb.apu.ch2.dac_enabled) {
                        gb.memory.io.nr24.trigger = false;

                        gb.apu.ch2.frequency = apu.frequency(gb, .ch2);

                        if (gb.apu.ch2.length.timer == 0) {
                            gb.apu.ch2.length.timer = 64;
                        }

                        gb.apu.ch2.envelope.timer = if (gb.memory.io.nr22.pace > 0)
                            gb.memory.io.nr22.pace
                        else
                            8;
                        gb.apu.ch2.envelope.value = gb.memory.io.nr22.initial_volume;

                        gb.memory.io.nr52.ch2_on = true;
                    }
                },
                0xff1a => {
                    gb.apu.ch3.dac_enabled = value & 0x80 != 0;
                    if (!gb.apu.ch3.dac_enabled) {
                        gb.memory.io.nr52.ch3_on = false;
                    }
                },
                0xff1b => {
                    gb.memory.io.nr31 = value;
                    gb.apu.ch3.length.timer = @as(u9, 256) - gb.memory.io.nr31;
                },
                0xff1c => gb.memory.io.nr32 = @enumFromInt(@as(u2, @truncate(value >> 5))),
                0xff1d => gb.memory.io.nr33 = value,
                0xff1e => {
                    gb.memory.io.nr34 = @bitCast(0b00111000 | value);

                    if (gb.memory.io.nr34.trigger and gb.apu.ch3.dac_enabled) {
                        gb.memory.io.nr34.trigger = false;

                        if (gb.apu.ch3.length.timer == 0) {
                            gb.apu.ch3.length.timer = 256;
                        }

                        gb.apu.ch3.frequency = apu.frequency(gb, .ch3);
                        gb.memory.io.nr52.ch3_on = true;
                    }
                },
                0xff20 => {
                    gb.memory.io.nr41 = @truncate(value);
                    gb.apu.ch4.length.timer = @as(u7, 64) - gb.memory.io.nr41;
                },
                0xff21 => {
                    gb.memory.io.nr42 = @bitCast(value);
                    gb.apu.ch4.dac_enabled = gb.memory.io.nr42.initial_volume != 0 or
                        gb.memory.io.nr42.envelope_direction != .decreasing;
                    if (!gb.apu.ch4.dac_enabled) {
                        gb.memory.io.nr52.ch4_on = false;
                    }
                },
                0xff22 => gb.memory.io.nr43 = @bitCast(value),
                0xff23 => {
                    gb.memory.io.nr44 = @bitCast(0x3f | value);

                    if (gb.memory.io.nr44.trigger and gb.apu.ch4.dac_enabled) {
                        gb.memory.io.nr44.trigger = false;

                        gb.apu.ch4.lfsr = math.maxInt(u15);

                        if (gb.apu.ch4.length.timer == 0) {
                            gb.apu.ch4.length.timer = 64;
                        }

                        gb.apu.ch4.envelope.timer = if (gb.memory.io.nr42.pace > 0)
                            gb.memory.io.nr42.pace
                        else
                            8;
                        gb.apu.ch4.envelope.value = gb.memory.io.nr42.initial_volume;

                        gb.memory.io.nr52.ch4_on = true;
                    }
                },
                0xff24 => gb.memory.io.nr50 = @bitCast(value),
                0xff25 => gb.memory.io.nr51 = @bitCast(value),
                else => {},
            }
        },
        0xff26 => {
            gb.memory.io.nr52.enable = value & 0x80 != 0;
            if (!gb.memory.io.nr52.enable) {
                gb.memory.io.nr10.step = 0;
                gb.memory.io.nr10.direction = .increasing;
                gb.memory.io.nr10.pace = 0;
                gb.memory.io.nr11.initial_length_timer = math.maxInt(u6);
                gb.memory.io.nr11.duty_cycle = .eighth;
                gb.memory.io.nr12.pace = 0;
                gb.memory.io.nr12.envelope_direction = .decreasing;
                gb.memory.io.nr12.initial_volume = 0;
                gb.memory.io.nr13 = 0xff;
                gb.memory.io.nr14.period = math.maxInt(u3);
                gb.memory.io.nr14.length_enable = false;
                gb.memory.io.nr14.trigger = true;

                gb.memory.io.nr21.initial_length_timer = math.maxInt(u6);
                gb.memory.io.nr21.duty_cycle = .eighth;
                gb.memory.io.nr22.pace = 0;
                gb.memory.io.nr22.envelope_direction = .decreasing;
                gb.memory.io.nr22.initial_volume = 0;
                gb.memory.io.nr23 = 0xff;
                gb.memory.io.nr24.period = math.maxInt(u3);
                gb.memory.io.nr24.length_enable = false;
                gb.memory.io.nr24.trigger = true;

                gb.apu.ch3.dac_enabled = false;
                gb.memory.io.nr31 = 0xff;
                gb.memory.io.nr32 = .mute;
                gb.memory.io.nr33 = 0xff;
                gb.memory.io.nr34.period = math.maxInt(u3);
                gb.memory.io.nr34.length_enable = false;
                gb.memory.io.nr34.trigger = true;

                gb.memory.io.nr41 = math.maxInt(u6);
                gb.memory.io.nr42.pace = 0;
                gb.memory.io.nr42.envelope_direction = .decreasing;
                gb.memory.io.nr42.initial_volume = 0;
                gb.memory.io.nr43.clock_divider = 0;
                gb.memory.io.nr43.lfsr_width = .bit15;
                gb.memory.io.nr43.clock_shift = 0;
                gb.memory.io.nr44.length_enable = false;
                gb.memory.io.nr44.trigger = true;

                gb.memory.io.nr50.volume_right = 0;
                gb.memory.io.nr50.vin_right = false;
                gb.memory.io.nr50.volume_left = 0;
                gb.memory.io.nr50.vin_left = false;

                gb.memory.io.nr51.ch1_right = false;
                gb.memory.io.nr51.ch2_right = false;
                gb.memory.io.nr51.ch3_right = false;
                gb.memory.io.nr51.ch4_right = false;
                gb.memory.io.nr51.ch1_left = false;
                gb.memory.io.nr51.ch2_left = false;
                gb.memory.io.nr51.ch3_left = false;
                gb.memory.io.nr51.ch4_left = false;

                gb.memory.io.nr52.ch1_on = false;
                gb.memory.io.nr52.ch2_on = false;
                gb.memory.io.nr52.ch3_on = false;
                gb.memory.io.nr52.ch4_on = false;
            }
        },
        inline 0xff30...0xff3f => |a| {
            const idx: u4 = @truncate(a);
            gb.memory.io.wave_pattern_ram[idx] = @bitCast(value);
        },
        0xff40 => {
            gb.memory.io.lcdc = @bitCast(value);
            if (!gb.memory.io.lcdc.lcd_enable) {
                @memset(gb.ppu.back_pixels, @bitCast(@as(u32, 0)));
            }
        },
        0xff41 => gb.memory.io.stat = @bitCast(
            (@as(u8, @bitCast(gb.memory.io.stat)) & 0x87) | (value & 0x78),
        ),
        0xff42 => gb.memory.io.scy = value,
        0xff43 => gb.memory.io.scx = value,
        0xff45 => gb.memory.io.lyc = value,
        0xff46 => {
            gb.memory.io.dma = value;
            // TODO: naive
            const start: Addr = @as(u16, value) << 8;
            for (0..0xa0) |offset| {
                const byte = readByte(gb, start + @as(u16, @intCast(offset)));
                gb.memory.oam[offset] = byte;
            }
        },
        0xff47 => gb.memory.io.bgp = @bitCast(value),
        0xff48 => gb.memory.io.obp0 = @bitCast(value),
        0xff49 => gb.memory.io.obp1 = @bitCast(value),
        0xff4a => gb.memory.io.wy = value,
        0xff4b => gb.memory.io.wx = value,
        0xff4c => {
            if (gb.memory.io.boot_rom_finished)
                return;

            gb.memory.io.key0 = @enumFromInt(@as(u1, @truncate(value >> 2)));
        },
        0xff4d => gb.memory.io.key1.armed = value & 1 != 0,
        0xff4f => gb.memory.io.vbk = @truncate(value),
        0xff50 => {
            gb.memory.io.boot_rom_finished =
                gb.memory.io.boot_rom_finished or value != 0;
        },
        0xff51 => gb.memory.io.hdma1 = value,
        0xff52 => gb.memory.io.hdma2 = value & 0xf0,
        0xff53 => gb.memory.io.hdma3 = value & 0x0f,
        0xff54 => gb.memory.io.hdma4 = value & 0xf0,
        0xff55 => {
            gb.memory.io.hdma5 = @bitCast(value);

            // TODO: naive
            const src = @as(u16, gb.memory.io.hdma1) << 8 | gb.memory.io.hdma2;
            const dst = @as(u16, gb.memory.io.hdma3) << 8 | gb.memory.io.hdma4;
            const length = (@as(u16, gb.memory.io.hdma5.length) + 1) * 0x10;

            for (0..length) |off| {
                const src_addr: Addr = src + @as(u16, @intCast(off));
                const dst_addr: Addr = dst + @as(u16, @intCast(off));

                const byte = readByte(gb, src_addr);
                writeByte(gb, dst_addr, byte);
            }

            gb.memory.io.hdma5 = @bitCast(@as(u8, 0xff));
        },
        0xff68 => gb.memory.io.bcps_bgpi = @bitCast(0x40 | value),
        0xff69 => {
            gb.ppu.bg_color_ram[gb.memory.io.bcps_bgpi.addr] = value;
            if (gb.memory.io.bcps_bgpi.auto_increment) {
                gb.memory.io.bcps_bgpi.addr +%= 1;
            }
        },
        0xff6a => gb.memory.io.ocps_obpi = @bitCast(0x40 | value),
        0xff6b => {
            gb.ppu.obj_color_ram[gb.memory.io.ocps_obpi.addr] = value;
            if (gb.memory.io.ocps_obpi.auto_increment) {
                gb.memory.io.ocps_obpi.addr +%= 1;
            }
        },
        0xff6c => gb.memory.io.opri = @enumFromInt(@as(u1, @truncate(value))),
        0xff70 => {
            gb.memory.io.svbk = @truncate(value);
            if (gb.memory.io.svbk == 0) {
                gb.memory.io.svbk = 1;
            }
        },
        else => {},
    }
}

fn write_hram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.hram[addr - HRAM_START] = value;
}

fn write_ie(gb: *gameboy.State, value: u8) void {
    gb.memory.io.ie = @bitCast(value);
}
