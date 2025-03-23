const std = @import("std");
const allocator = std.heap.wasm_allocator;

const zgbc = @import("root.zig");
const cpu = zgbc.cpu;
const gameboy = zgbc.gameboy;
const ppu = zgbc.ppu;
const joypad = zgbc.joypad;
const memory = zgbc.memory;
const rom = zgbc.rom;

extern "env" fn rumbleChanged(on: bool) void;

pub const ByteArray = extern struct {
    ptr: [*]const u8,
    len: usize,
};

export fn allocUint8Array(len: u32) [*]const u8 {
    const slice = allocator.alloc(u8, len) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

export fn freeUint8Array(ptr: [*]const u8, len: u32) void {
    allocator.free(ptr[0..len]);
}

export fn init() ?*gameboy.State {
    const gb = allocator.create(gameboy.State) catch return null;
    gb.* = gameboy.State.init(allocator) catch return null;
    return gb;
}

export fn deinit(gb: *gameboy.State) void {
    gb.deinit(allocator);
}

export fn reset(gb: *gameboy.State) void {
    gb.reset(allocator);
}

export fn loadROM(gb: *gameboy.State, ptr: [*]u8, len: u32) void {
    rom.load(allocator, gb, ptr, len, rumbleChanged) catch return;
}

var title: ?ByteArray = null;
export fn romTitle(gb: *gameboy.State) ?*ByteArray {
    if (gb.memory.rom) |r| {
        title = .{
            .ptr = r.title.ptr,
            .len = r.title.len,
        };
    }

    return &(title orelse return null);
}

export fn supportsSaving(gb: *gameboy.State) bool {
    if (gb.memory.rom) |r| {
        return r.mbc.has_battery();
    }

    return false;
}

var sram: ?ByteArray = null;
export fn getBatteryBackedRAM(gb: *gameboy.State) ?*ByteArray {
    if (gb.memory.rom) |r| {
        if (r.mbc.has_battery()) {
            switch (r.mbc) {
                .mbc2_battery => |mbc2| {
                    sram = .{
                        .ptr = mbc2.builtin_ram,
                        .len = mbc2.builtin_ram.len,
                    };
                },
                else => {
                    sram = .{
                        .ptr = r.mbc_ram.ptr,
                        .len = r.mbc_ram.len,
                    };
                },
            }
        }
    }

    return &(sram orelse return null);
}

export fn setBatteryBackedRAM(gb: *gameboy.State, ptr: [*]u8, len: u32) void {
    if (gb.memory.rom) |*r| {
        if (r.mbc.has_battery()) {
            switch (r.mbc) {
                .mbc2_battery => |*mbc2| @memcpy(mbc2.builtin_ram, ptr[0..len]),
                else => @memcpy(r.mbc_ram, ptr[0..len]),
            }
        }
    }
}

/// Try to run for the given amount of `cycles`, returning the delta.
export fn stepCycles(gb: *gameboy.State, cycles: i32) i32 {
    const target_cycles = cycles;
    var consumed_cycles: i32 = 0;

    while (consumed_cycles < target_cycles) {
        const consumed = cpu.step(gb);
        consumed_cycles += consumed;
    }

    return target_cycles - consumed_cycles;
}

export fn pixels(gb: *gameboy.State) [*]ppu.Pixel {
    return gb.ppu.pixels;
}

export fn buttonPress(gb: *gameboy.State, button: joypad.Button) void {
    joypad.press(gb, button);
}

export fn buttonRelease(gb: *gameboy.State, button: joypad.Button) void {
    joypad.release(gb, button);
}

export fn readLeftAudioChannel(gb: *gameboy.State, ptr: [*]f32, len: u32) usize {
    return gb.apu.l_chan.read(ptr[0..len]);
}

export fn readRightAudioChannel(gb: *gameboy.State, ptr: [*]f32, len: u32) usize {
    return gb.apu.r_chan.read(ptr[0..len]);
}
