//! ROM cartridges and MBC mappers.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const gameboy = @import("gb.zig");

pub const MAX_TITLE_LEN = 15;
pub const ROM_HEADER_TITLE_START = 0x134;
pub const ROM_HEADER_CARTRIDGE_TYPE = 0x147;
pub const ROM_HEADER_RAM_SIZE = 0x149;

/// Tracks the internal state of the ROM/cartridge.
pub const State = struct {
    /// The raw bytes of the rom.
    data: []const u8,
    /// The title of the rom in all caps ASCII.
    title: []const u8,
    /// State of the memory bank controller.
    mbc: MbcState,
    /// External RAM in the cartridge.
    mbc_ram: []u8,

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        allocator.free(self.data);
        allocator.free(self.mbc_ram);

        switch (self.mbc) {
            .mbc2, .mbc2_battery => |mbc2| allocator.destroy(mbc2.builtin_ram),
            else => {},
        }
    }

    pub fn num_rom_banks(self: @This()) usize {
        return self.data.len / 0x4000;
    }

    pub fn num_ram_banks(self: @This()) usize {
        return self.mbc_ram.len / 0x2000;
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
    mbc5: Mbc5,
    mbc5_ram: Mbc5,
    mbc5_ram_battery: Mbc5,
    mbc5_rumble: Mbc5,
    mbc5_rumble_ram: Mbc5,
    mbc5_rumble_ram_battery: Mbc5,

    pub fn has_battery(self: @This()) bool {
        return switch (self) {
            .rom_only,
            .mbc1,
            .mbc1_ram,
            .mbc2,
            .mbc3,
            .mbc3_ram,
            .mbc5,
            .mbc5_ram,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            => false,
            .mbc1_ram_battery,
            .mbc2_battery,
            .mbc3_timer_battery,
            .mbc3_timer_ram_battery,
            .mbc3_ram_battery,
            .mbc5_ram_battery,
            .mbc5_rumble_ram_battery,
            => true,
        };
    }
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
    mbc5 = 0x19,
    mbc5_ram = 0x1a,
    mbc5_ram_battery = 0x1b,
    mbc5_rumble = 0x1c,
    mbc5_rumble_ram = 0x1d,
    mbc5_rumble_ram_battery = 0x1e,
};

/// Register state for mbc 1.
pub const Mbc1 = struct {
    /// Enables external RAM.
    mbc_ram_enable: bool,
    /// Which ROM bank to read from.
    rom_bank: u5,
    /// Which RAM bank to read from.
    ram_bank: u2,
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

/// Register state for mbc 5.
pub const Mbc5 = struct {
    /// Enables external RAM.
    mbc_ram_enable: bool,
    /// Which ROM bank to read from.
    rom_bank: u9,
    /// Which RAM bank to read from.
    ram_bank: u4,
    /// Whether rumble is active.
    rumble_active: bool,
};

/// Called when rumble state is changed, can't be part of the state
/// register state since it doesn't work with the wasm calling convention.
pub var rumble_changed: ?*const fn (bool) callconv(.c) void = null;

/// Loads a ROM cartridge and sets up some state based on the header.
pub fn load(
    allocator: mem.Allocator,
    gb: *gameboy.State,
    ptr: [*]u8,
    len: u32,
    rumble_changed_callback: ?*const fn (bool) callconv(.c) void,
) !void {
    rumble_changed = rumble_changed_callback;
    gb.memory.rom = .{
        .data = ptr[0..len],
        .title = value: {
            const title_ptr: [*:0]u8 = @ptrCast(&ptr[ROM_HEADER_TITLE_START]);
            const title_len = mem.len(title_ptr);
            break :value title_ptr[0..@min(MAX_TITLE_LEN, title_len)];
        },
        .mbc = switch (@as(CartridgeType, @enumFromInt(ptr[ROM_HEADER_CARTRIDGE_TYPE]))) {
            .rom_only => .{ .rom_only = .{} },
            inline .mbc1, .mbc1_ram, .mbc1_ram_battery => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 1,
                    .ram_bank = 0,
                },
            ),
            inline .mbc2, .mbc2_battery => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 1,
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
                    .rom_bank = 1,
                    .ram_bank = 0,
                    .mode = .ram,
                },
            ),
            inline .mbc5,
            .mbc5_ram,
            .mbc5_ram_battery,
            .mbc5_rumble,
            .mbc5_rumble_ram,
            .mbc5_rumble_ram_battery,
            => |variant| @unionInit(
                MbcState,
                @tagName(variant),
                .{
                    .mbc_ram_enable = false,
                    .rom_bank = 0,
                    .ram_bank = 0,
                    .rumble_active = false,
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
