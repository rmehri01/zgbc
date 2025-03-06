const std = @import("std");

const gameboy = @import("gb.zig");
const memory = @import("memory.zig");

/// The stage of rendering the ppu is in for the current frame.
pub const Mode = enum(u2) {
    oam_scan = 2,
    vram_read = 3,
    h_blank = 0,
    v_blank = 1,
};

/// RGBA pixel value.
pub const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const colors = [4]Pixel{
    // White: #e0f8d0
    .{ .r = 224, .g = 248, .b = 208, .a = 255 },
    // Light Gray: #88c070
    .{ .r = 136, .g = 192, .b = 112, .a = 255 },
    // Dark Gray: #346856
    .{ .r = 52, .g = 104, .b = 86, .a = 255 },
    // Black: #081820
    .{ .r = 8, .g = 24, .b = 32, .a = 255 },
};

/// An object (or a sprite) is either 8x8 or 8x16 pixels and can be displayed anywhere.
const Object = packed struct(u32) {
    /// Y-coordinate of top left corner stored as y - 16 since it can be off the screen.
    y_pos: u8,
    /// X-coordinate of top left corner stored as y - 8 since it can be off the screen.
    x_pos: u8,
    /// Index into the tile data for this object's tile.
    tile_id: u8,
    flags: packed struct(u8) {
        /// (CGB only) Which of OBP0–7 to use.
        cgb_palette: u3,
        /// (CGB only) Which VRAM bank to fetch from.
        bank: u1,
        /// (non-CGB only) Which of OBP0-1 to use.
        dmg_palette: bool,
        /// Horizontally mirror the object.
        x_flip: bool,
        /// Vertically mirror the object.
        y_flip: bool,
        /// Whether the object is above or below the background and window.
        priority: enum(u1) { above = 0, below = 1 },
    },
};

/// Execute a single step of the ppu.
pub fn step(gb: *gameboy.State) void {
    gb.dots += gb.pending_cycles;

    switch (gb.mode) {
        .oam_scan => {
            if (gb.dots >= 80) {
                gb.dots = 0;
                gb.mode = .vram_read;
            }
        },
        .vram_read => {
            if (gb.dots >= 172) {
                gb.dots = 0;
                gb.mode = .h_blank;

                render_line(gb);
            }
        },
        .h_blank => {
            if (gb.dots >= 204) {
                gb.dots = 0;
                gb.io_registers.ly += 1;

                if (gb.io_registers.ly == 144) {
                    gb.mode = .v_blank;
                    gb.io_registers.intf.v_blank = true;
                } else {
                    gb.mode = .oam_scan;
                }
            }
        },
        .v_blank => {
            if (gb.dots >= 456) {
                gb.dots = 0;
                gb.io_registers.ly += 1;

                if (gb.io_registers.ly > 153) {
                    gb.mode = .oam_scan;
                    gb.io_registers.ly = 0;
                }
            }
        },
    }
}

fn render_line(gb: *gameboy.State) void {
    const y_pixel = gb.io_registers.ly +% gb.io_registers.scy;
    const x_pixel_start = gb.io_registers.scx;

    const bg_tile_map_start: memory.Addr = switch (gb.io_registers.lcdc.bg_tile_map_area) {
        0 => memory.TILE_MAP0_START,
        1 => memory.TILE_MAP1_START,
    };
    const data_area_start: memory.Addr = switch (gb.io_registers.lcdc.bg_window_tile_data_area) {
        .signed => memory.TILE_BLOCK2_START,
        .unsigned => memory.TILE_BLOCK0_START,
    };

    if (gb.io_registers.lcdc.bg_window_enable_priority) {
        for (0..160) |x_pixel_off| {
            const x_pixel = x_pixel_start +% x_pixel_off;

            const tile_id = gb.vram[bg_tile_map_start + (@as(u16, y_pixel) / 8) * 32 + (x_pixel / 8) - memory.VRAM_START];
            var tile_addr = switch (gb.io_registers.lcdc.bg_window_tile_data_area) {
                .signed => value: {
                    const offset: i8 = @bitCast(tile_id);
                    break :value if (offset < 0)
                        data_area_start - @abs(offset)
                    else
                        data_area_start + @abs(offset);
                },
                .unsigned => data_area_start + @as(u16, tile_id) * 16,
            };

            tile_addr += (y_pixel % 8) * 2;

            const tile_data1 = gb.vram[tile_addr - memory.VRAM_START];
            const tile_data2 = gb.vram[tile_addr + 1 - memory.VRAM_START];

            const lo = tile_data1 & (@as(u8, 0x80) >> @intCast(x_pixel % 8)) != 0;
            const hi = tile_data2 & (@as(u8, 0x80) >> @intCast(x_pixel % 8)) != 0;

            const palette_id = @as(u2, @intFromBool(hi)) << 1 | @intFromBool(lo);
            const color_id = switch (palette_id) {
                0 => gb.io_registers.bgp.id0,
                1 => gb.io_registers.bgp.id1,
                2 => gb.io_registers.bgp.id2,
                3 => gb.io_registers.bgp.id3,
            };
            gb.pixels[@as(u16, gb.io_registers.ly) * 160 + x_pixel_off] = colors[color_id];
        }
    }
}
