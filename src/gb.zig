const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const cpu = @import("cpu.zig");
const ppu = @import("ppu.zig");

const dmg_boot_rom = @embedFile("boot/dmg.bin");

/// The main state of the gameboy emulator.
pub const State = struct {
    /// Interrupt Master Enable, enables the jump to the interrupt vectors,
    /// not whether interrupts are enabled or disabled.
    ime: bool,
    /// The ei instruction has a delayed effect that will enable interrupt
    /// handling after one machine cycle.
    scheduled_ei: bool,
    /// State of the registers in the gameboy.
    registers: RegisterFile,
    /// The number of t-cycles that are pending.
    pending_cycles: u8,

    /// The boot ROM to use when starting up.
    boot_rom: []const u8,
    /// The cartridge that is currently loaded.
    rom: ?[]u8,
    /// Video RAM.
    vram: *[0x2000]u8,
    /// Work RAM.
    ram: *[0x2000]u8,
    /// Object attribute memory.
    oam: *[0xa0]u8,
    /// High RAM.
    hram: *[0x7f]u8,
    /// Memory mapped I/O registers.
    io_registers: struct {
        lcdc: packed struct(u8) {
            /// In non-CGB mode, when cleared, the background and window are blank.
            /// In CGB mode, when cleared, the background and window lose priority.
            bg_window_clear_priority: bool,
            /// Whether objects are displayed or not.
            obj_enable: bool,
            /// Controls the size of objects (1 or 2 tiles vertically).
            obj_size: bool,
            /// If the bit is clear, the background uses tilemap 0x9800, otherwise
            /// tilemap 0x9c00.
            bg_tile_map_area: bool,
            /// If the bit is clear, the background and window use the 0x8800 method,
            /// otherwise they use the 0x8000 method.
            bg_window_tile_data_area: bool,
            /// Whether the window is displayed or not.
            window_enable: bool,
            /// If the bit is clear, the window uses tilemap 0x9800, otherwise
            /// tilemap 0x9c00.
            window_tile_map_area: bool,
            /// Whether the LCD is on and the PPU is active.
            lcd_enable: bool,
        },
        /// Background viewport Y position.
        scy: u8,
        /// Background viewport X position.
        scx: u8,
        /// LCD Y coordinate, the current line that is being drawn in the ppu.
        ly: u8,
        /// Background palette data.
        bgp: packed struct(u8) {
            id0: u2,
            id1: u2,
            id2: u2,
            id3: u2,
        },
    },

    /// The current rendering mode the ppu is in.
    mode: ppu.Mode,
    /// The number of horizontal time units that have passed in the ppu.
    dots: u16,
    /// The pixels corresponding to the current state of the display.
    pixels: *[144 * 160]ppu.Pixel,

    pub fn tick(self: *@This()) void {
        // TODO: naive
        self.pending_cycles += 4;
    }

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .ime = false,
            .scheduled_ei = false,
            .registers = .{ .named16 = .{ .af = 0, .bc = 0, .de = 0, .hl = 0, .sp = 0, .pc = 0 } },
            .pending_cycles = 0,

            .boot_rom = dmg_boot_rom,
            .rom = null,
            .vram = try allocator.create([0x2000]u8),
            .ram = try allocator.create([0x2000]u8),
            .oam = try allocator.create([0xa0]u8),
            .hram = try allocator.create([0x7f]u8),
            .io_registers = .{
                .lcdc = .{
                    .bg_window_clear_priority = false,
                    .obj_enable = false,
                    .obj_size = false,
                    .bg_tile_map_area = false,
                    .bg_window_tile_data_area = false,
                    .window_enable = false,
                    .window_tile_map_area = false,
                    .lcd_enable = false,
                },
                .scy = 0,
                .scx = 0,
                .ly = 0,
                .bgp = .{
                    .id0 = 0,
                    .id1 = 0,
                    .id2 = 0,
                    .id3 = 0,
                },
            },

            .mode = .oam_scan,
            .dots = 0,
            .pixels = try allocator.create([144 * 160]ppu.Pixel),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.rom) |rom| {
            allocator.free(rom);
        }

        allocator.destroy(self.vram);
        allocator.destroy(self.ram);
        allocator.destroy(self.oam);
        allocator.destroy(self.hram);
        allocator.destroy(self.pixels);
    }
};

/// Most registers can be accessed as one 16-bit register
/// or as two separate 8-bit registers so we use a C style union.
const RegisterFile = extern union {
    named16: extern struct {
        af: u16,
        bc: u16,
        de: u16,
        hl: u16,
        sp: u16,
        pc: u16,
    },
    named8: extern struct {
        f: cpu.Flags,
        a: u8,
        c: u8,
        b: u8,
        e: u8,
        d: u8,
        l: u8,
        h: u8,
    },

    comptime {
        assert(@sizeOf(@This()) == 6 * @sizeOf(u16));
    }

    pub fn jsonStringify(
        self: @This(),
        writer: anytype,
    ) !void {
        try writer.beginObject();

        inline for (@typeInfo(RegisterFile).@"union".fields) |unionField| {
            try writer.objectField(unionField.name);
            try writer.beginObject();

            inline for (@typeInfo(unionField.type).@"struct".fields) |field| {
                try writer.objectField(field.name);
                try writer.write(@field(@field(self, unionField.name), field.name));
            }

            try writer.endObject();
        }

        try writer.endObject();
    }
};

test "RegisterFile get" {
    const registers = RegisterFile{ .named16 = .{ .af = 0x1234, .bc = 0, .de = 0, .hl = 0xbeef, .sp = 0, .pc = 0 } };

    try testing.expectEqual(0x12, registers.named8.a);
    try testing.expectEqual(0xef, registers.named8.l);
}

test "RegisterFile set" {
    var registers = RegisterFile{ .named16 = .{ .af = 0, .bc = 0, .de = 0xfeed, .hl = 0, .sp = 0, .pc = 0 } };

    registers.named8.d = 0xaa;
    try testing.expectEqual(0xaa, registers.named8.d);
    try testing.expectEqual(0xaaed, registers.named16.de);

    registers.named8.e = 0xbb;
    try testing.expectEqual(0xaabb, registers.named16.de);
}
