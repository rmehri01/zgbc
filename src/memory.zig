//! Memory interface for ROM, RAM, and memory mapped I/O.

const std = @import("std");
const testing = std.testing;
const math = std.math;
const mem = std.mem;

const apu = @import("apu.zig");
const gameboy = @import("gb.zig");
const ppu = @import("ppu.zig");

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
pub const OAM_START = 0xfe00;
pub const HRAM_START = 0xff80;

pub const ROM_HEADER_CARTRIDGE_TYPE = 0x147;
pub const ROM_HEADER_RAM_SIZE = 0x149;

const dmg_boot_rom = @embedFile("boot/dmg.bin");

/// Tracks the internal state of memory.
pub const State = struct {
    /// The boot ROM to use when starting up.
    boot_rom: []const u8,
    /// The cartridge that is currently loaded.
    rom: ?struct {
        /// The raw bytes of the rom.
        data: []const u8,
        /// State of the memory bank controller.
        mbc: MbcState,
        /// External RAM in the cartridge.
        mbc_ram: []u8,
    },
    /// Video RAM.
    vram: *[0x2000]u8,
    /// Work RAM.
    ram: *[0x2000]u8,
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
            /// (non-CGB only) When cleared, the background and window are blank.
            /// (CGB only) When cleared, the background and window lose priority.
            bg_window_enable_priority: bool,
            /// Whether objects are displayed or not.
            obj_enable: bool,
            /// Controls the size of objects (1 or 2 tiles vertically).
            obj_size: bool,
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
        /// Background palette data.
        bgp: packed struct(u8) {
            id0: u2,
            id1: u2,
            id2: u2,
            id3: u2,
        },
        /// Object palette data 0.
        obp0: ppu.ObjectPalette,
        /// Object palette data 1.
        obp1: ppu.ObjectPalette,
        /// Window Y position.
        wy: u8,
        /// Window X position plus 7.
        wx: u8,
        /// Set to non-zero to disable boot ROM, cannot be unset.
        boot_rom_finished: bool,
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
        return @This(){
            .boot_rom = dmg_boot_rom,
            .rom = null,
            .vram = try allocator.create([0x2000]u8),
            .ram = try allocator.create([0x2000]u8),
            .oam = try allocator.create([0xa0]u8),
            .hram = try allocator.create([0x7f]u8),
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
                    .obj_size = false,
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
                .boot_rom_finished = false,
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

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        if (self.rom) |rom| {
            allocator.free(rom.data);
            allocator.free(rom.mbc_ram);

            switch (rom.mbc) {
                .mbc2, .mbc2_battery => |mbc2| allocator.destroy(mbc2.builtin_ram),
                else => {},
            }
        }

        allocator.destroy(self.vram);
        allocator.destroy(self.ram);
        allocator.destroy(self.oam);
        allocator.destroy(self.hram);
    }
};

/// Memory bank controller state which is specific to the kind of mapper.
pub const MbcState = union(CartridgeType) {
    rom_only: struct {},
    mbc1: Mbc1,
    mbc1_ram: Mbc1,
    mbc1_ram_battery: Mbc1,
    mbc2: Mbc2,
    mbc2_battery: Mbc2,
    mbc3_timer_battery: Mbc3,
    mbc3_timer_ram_battery: Mbc3,
    mbc3: Mbc3,
    mbc3_ram: Mbc3,
    mbc3_ram_battery: Mbc3,
};

/// Determines the type of mapper.
pub const CartridgeType = enum(u8) {
    rom_only = 0x00,
    mbc1 = 0x01,
    mbc1_ram = 0x02,
    mbc1_ram_battery = 0x03,
    mbc2 = 0x05,
    mbc2_battery = 0x06,
    mbc3_timer_battery = 0x0f,
    mbc3_timer_ram_battery = 0x10,
    mbc3 = 0x11,
    mbc3_ram = 0x12,
    mbc3_ram_battery = 0x13,
};

/// Register state for mbc 1.
pub const Mbc1 = struct {
    /// Enables external RAM.
    mbc_ram_enable: bool,
    /// Which ROM bank to read from.
    rom_bank: u7,
    /// Which RAM bank to read from.
    ram_bank: u2,
    /// Determines whether to use space as extra rom or extra external ram.
    mode: enum(u1) {
        rom = 0,
        ram = 1,
    },
};

/// Register state for mbc 2.
pub const Mbc2 = struct {
    /// Enables external RAM.
    mbc_ram_enable: bool,
    /// Which ROM bank to read from.
    rom_bank: u4,
    /// The chip includes 512 nibbles of RAM, only the lower 4 bits of each byte are used.
    builtin_ram: *[512]u8,
};

/// Register state for mbc 3.
pub const Mbc3 = struct {
    /// Enables external RAM.
    mbc_ram_enable: bool,
    /// Which ROM bank to read from.
    rom_bank: u7,
    /// Which RAM bank to read from.
    ram_bank: u3,
    /// Determines whether to access external RAM or the RTC register.
    mode: enum { ram, rtc },
};

/// Loads a ROM cartridge and sets up some state based on the header.
pub fn loadROM(allocator: mem.Allocator, gb: *gameboy.State, ptr: [*]u8, len: u32) !void {
    gb.memory.rom = .{
        .data = ptr[0..len],
        .mbc = switch (@as(CartridgeType, @enumFromInt(ptr[ROM_HEADER_CARTRIDGE_TYPE]))) {
            .rom_only => .{ .rom_only = .{} },
            inline .mbc1, .mbc1_ram, .mbc1_ram_battery => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 0,
                    .ram_bank = 0,
                    .mode = .rom,
                },
            ),
            inline .mbc2, .mbc2_battery => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 0,
                    .builtin_ram = try allocator.create([512]u8),
                },
            ),
            inline .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 0,
                    .ram_bank = 0,
                    .mode = .ram,
                },
            ),
        },
        .mbc_ram = value: {
            const num_banks: u16 = switch (ptr[ROM_HEADER_RAM_SIZE]) {
                0 => 0,
                1 => 0,
                2 => 1,
                3 => 4,
                4 => 16,
                5 => 8,
                else => unreachable,
            };
            const mbc_ram = try allocator.alloc(u8, num_banks * 0x2000);
            break :value mbc_ram;
        },
    };
}

/// Reads a single byte at the given `Addr`, delegating it
/// to the correct handler.
pub fn readByte(gb: *gameboy.State, addr: Addr) u8 {
    return switch (addr) {
        0x0000...0x3fff => read_rom(gb, addr),
        0x4000...0x7fff => read_mbc_rom(gb, addr),
        0x8000...0x9fff => read_vram(gb, addr),
        0xa000...0xbfff => read_mbc_ram(gb, addr),
        0xc000...0xcfff => read_ram(gb, addr),
        0xd000...0xdfff => read_banked_ram(gb, addr),
        // TODO: clean up
        0xe000...0xfdff => read_ram(gb, addr - 0x2000),
        0xfe00...0xfe9f => read_oam(gb, addr),
        0xfea0...0xfeff => read_not_usable(gb, addr),
        0xff00...0xff7f => read_io_registers(gb, addr),
        0xff80...0xfffe => read_hram(gb, addr),
        0xffff => read_ie(gb),
    };
}

fn read_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (!gb.memory.io.boot_rom_finished and addr < 0x100) {
        return gb.memory.boot_rom[addr];
    }

    if (gb.memory.rom) |rom| {
        return rom.data[addr];
    }

    return 0xff;
}

fn read_mbc_rom(gb: *gameboy.State, addr: Addr) u8 {
    if (gb.memory.rom) |rom| {
        const bank = switch (rom.mbc) {
            .rom_only => 1,
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |mbc1| mbc1.rom_bank,
            .mbc2, .mbc2_battery => |mbc2| mbc2.rom_bank,
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3,
            .mbc3_ram,
            .mbc3_ram_battery,
            => |mbc3| mbc3.rom_bank,
        };
        return rom.data[bank * @as(u32, 0x4000) + (addr - MBC_ROM_START)];
    }

    return 0xff;
}

fn read_vram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.vram[addr - VRAM_START];
}

fn read_mbc_ram(gb: *gameboy.State, addr: Addr) u8 {
    if (gb.memory.rom) |rom| {
        const bank: u16 = switch (rom.mbc) {
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
        };

        if (rom.mbc_ram.len == 0) {
            return 0xff;
        } else {
            return rom.mbc_ram[bank * @as(u16, 0x2000) + (addr - MBC_RAM_START)];
        }
    }

    return 0xff;
}

fn read_ram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.ram[addr - RAM_START];
}

fn read_banked_ram(gb: *gameboy.State, addr: Addr) u8 {
    return gb.memory.ram[addr - RAM_START];
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
        0xff11 => @bitCast(gb.memory.io.nr11),
        0xff12 => @bitCast(gb.memory.io.nr12),
        0xff13 => gb.memory.io.nr13,
        0xff14 => @bitCast(gb.memory.io.nr14),
        0xff16 => @bitCast(gb.memory.io.nr21),
        0xff17 => @bitCast(gb.memory.io.nr22),
        0xff18 => gb.memory.io.nr23,
        0xff19 => @bitCast(gb.memory.io.nr24),
        0xff1a => @as(u8, @intFromBool(gb.apu.ch3.dac_enabled)) << 7 | @as(u8, 0x7f),
        0xff1b => @bitCast(gb.memory.io.nr31),
        0xff1c => 0x6f | @as(u8, @intFromEnum(gb.memory.io.nr32)) << 5,
        0xff1d => gb.memory.io.nr33,
        0xff1e => @bitCast(gb.memory.io.nr34),
        0xff20 => @as(u8, 0xc0) | gb.memory.io.nr41,
        0xff21 => @bitCast(gb.memory.io.nr42),
        0xff22 => @bitCast(gb.memory.io.nr43),
        0xff23 => @bitCast(gb.memory.io.nr44),
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
        0xff50 => @as(u8, 0xfe) | @intFromBool(gb.memory.io.boot_rom_finished),
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
        // TODO: clean up
        0xe000...0xfdff => write_ram(gb, addr - 0x2000, value),
        0xfe00...0xfe9f => write_oam(gb, addr, value),
        0xfea0...0xfeff => write_not_usable(gb, addr, value),
        0xff00...0xff7f => write_io_registers(gb, addr, value),
        0xff80...0xfffe => write_hram(gb, addr, value),
        0xffff => write_ie(gb, value),
    };
}

fn write_mbc_rom(gb: *gameboy.State, addr: Addr, value: u8) void {
    if (gb.memory.rom) |*rom| {
        switch (rom.mbc) {
            .rom_only => {},
            .mbc1, .mbc1_ram, .mbc1_ram_battery => |*mbc1| switch ((addr & 0xf000) >> 12) {
                0x0, 0x1 => mbc1.mbc_ram_enable = (value & 0x0f) == 0x0a,
                0x2, 0x3 => {
                    var lo: u7 = @intCast(value & 0x1f);
                    if (lo == 0) {
                        lo = 1;
                    }

                    mbc1.rom_bank = (mbc1.rom_bank & 0x60) | lo;
                },
                0x4, 0x5 => switch (mbc1.mode) {
                    .rom => mbc1.rom_bank =
                        @as(u7, @intCast(value & 0b11)) << 5 | (mbc1.rom_bank & 0x1f),
                    .ram => mbc1.ram_bank = @intCast(value & 0b11),
                },
                else => unreachable,
            },
            .mbc2, .mbc2_battery => |*mbc2| if ((addr & 0x0100) != 0) {
                var lo: u4 = @intCast(value & 0x0f);
                if (lo == 0) {
                    lo = 1;
                }

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

                    mbc3.rom_bank = lo;
                },
                0x4, 0x5 => if (value <= 0x07) {
                    mbc3.mode = .ram;
                    mbc3.ram_bank = @intCast(value);
                } else if (value <= 0x0c) {
                    mbc3.mode = .rtc;
                },
                0x6, 0x7 => {},
                else => unreachable,
            },
        }
    }
}

fn write_vram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.vram[addr - VRAM_START] = value;
}

fn write_mbc_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    if (gb.memory.rom) |*rom| {
        const bank = switch (rom.mbc) {
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
        };

        if (rom.mbc_ram.len == 0) {
            return;
        } else {
            rom.mbc_ram[bank * @as(u16, 0x2000) + (addr - MBC_RAM_START)] = value;
        }
    }
}

fn write_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.ram[addr - RAM_START] = value;
}

fn write_banked_ram(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.ram[addr - RAM_START] = value;
}

fn write_oam(gb: *gameboy.State, addr: Addr, value: u8) void {
    gb.memory.oam[addr - OAM_START] = value;
}

fn write_not_usable(gb: *gameboy.State, addr: Addr, value: u8) void {
    _ = gb;
    _ = addr;
    _ = value;
    // @panic("unimplemented");
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
                    gb.memory.io.nr14 = @bitCast(0b00111000 | value);

                    if (gb.memory.io.nr14.trigger) {
                        gb.memory.io.nr14.trigger = false;

                        if (!gb.memory.io.nr52.ch1_on) {
                            gb.apu.ch1.position = 0;
                        }

                        gb.apu.ch1.frequency = apu.frequency(gb, .ch1);

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

                    if (gb.memory.io.nr24.trigger) {
                        gb.memory.io.nr24.trigger = false;

                        if (!gb.memory.io.nr52.ch2_on) {
                            gb.apu.ch2.position = 0;
                        }

                        gb.apu.ch2.frequency = apu.frequency(gb, .ch2);

                        gb.apu.ch2.envelope.timer = if (gb.memory.io.nr22.pace > 0)
                            gb.memory.io.nr22.pace
                        else
                            8;
                        gb.apu.ch2.envelope.value = gb.memory.io.nr22.initial_volume;

                        gb.memory.io.nr52.ch2_on = true;
                    }
                },
                0xff1a => gb.apu.ch3.dac_enabled = value & 0x80 != 0,
                0xff1b => {
                    gb.memory.io.nr31 = value;
                    gb.apu.ch3.length.timer = @as(u9, 256) - gb.memory.io.nr31;
                },
                0xff1c => gb.memory.io.nr32 = @enumFromInt(@as(u2, @truncate(value >> 5))),
                0xff1d => gb.memory.io.nr33 = value,
                0xff1e => {
                    gb.memory.io.nr34 = @bitCast(0b00111000 | value);

                    if (gb.memory.io.nr34.trigger) {
                        gb.memory.io.nr34.trigger = false;

                        if (!gb.memory.io.nr52.ch3_on) {
                            gb.apu.ch3.position = 0;
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

                    if (gb.memory.io.nr44.trigger) {
                        gb.memory.io.nr44.trigger = false;

                        gb.apu.ch4.lfsr = math.maxInt(u15);
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
        0xff40 => gb.memory.io.lcdc = @bitCast(value),
        0xff41 => gb.memory.io.stat = @bitCast(0x80 | value),
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
        0xff50 => {
            gb.memory.io.boot_rom_finished =
                gb.memory.io.boot_rom_finished or value != 0;
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
