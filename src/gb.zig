const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

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

    pub fn tick(self: *@This()) void {
        _ = self; // autofix
    }

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .ime = false,
            .scheduled_ei = false,
            .registers = .{ .named16 = .{ .af = 0, .bc = 0, .de = 0, .hl = 0, .sp = 0, .pc = 0 } },
            .boot_rom = dmg_boot_rom,
            .rom = null,
            .vram = try allocator.create([0x2000]u8),
            .ram = try allocator.create([0x2000]u8),
            .oam = try allocator.create([0xa0]u8),
            .hram = try allocator.create([0x7f]u8),
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
        f: Flags,
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

/// Contains information about the result of the most recent CPU
/// instruction that has affected flags.
const Flags = packed struct(u8) {
    _: u4 = 0,
    /// Carry flag.
    c: bool,
    /// Half Carry flag (BCD).
    h: bool,
    /// Subtraction flag (BCD).
    n: bool,
    /// Zero flag.
    z: bool,
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
