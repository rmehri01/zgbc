//! Pixel Processing Unit.

const std = @import("std");
const mem = std.mem;
const math = std.math;

const gameboy = @import("gb.zig");
const memory = @import("memory.zig");

pub const SCREEN_WIDTH = 160;
pub const SCREEN_HEIGHT = 144;

/// Tracks the internal state of the ppu.
pub const State = struct {
    /// The number of horizontal time units that have passed in the ppu.
    dots: u16,
    /// The pixels corresponding to the current state of the display.
    front_pixels: *[SCREEN_WIDTH * SCREEN_HEIGHT]Pixel,
    /// The pixels corresponding to the next state of the display.
    back_pixels: *[SCREEN_WIDTH * SCREEN_HEIGHT]Pixel,
    /// Internal line counter similar to `ly` that only gets incremented when
    /// the window is visible.
    window_line: u8,
    /// (CGB only) Specifies the 8 background color palettes.
    bg_color_ram: [0x40]u8,
    /// (CGB only) Specifies the 8 object color palettes.
    obj_color_ram: [0x40]u8,

    pub fn init(allocator: mem.Allocator) !@This() {
        const front_pixels = try allocator.create([SCREEN_WIDTH * SCREEN_HEIGHT]Pixel);
        const back_pixels = try allocator.create([SCREEN_WIDTH * SCREEN_HEIGHT]Pixel);

        return @This().initWithMem(front_pixels, back_pixels);
    }

    pub fn reset(self: @This()) @This() {
        return @This().initWithMem(self.front_pixels, self.back_pixels);
    }

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        allocator.destroy(self.front_pixels);
        allocator.destroy(self.back_pixels);
    }

    fn initWithMem(
        front_pixels: *[SCREEN_WIDTH * SCREEN_HEIGHT]Pixel,
        back_pixels: *[SCREEN_WIDTH * SCREEN_HEIGHT]Pixel,
    ) @This() {
        return @This(){
            .dots = 0,
            .front_pixels = front_pixels,
            .back_pixels = back_pixels,
            .window_line = 0,
            .bg_color_ram = [_]u8{0} ** 0x40,
            .obj_color_ram = [_]u8{0} ** 0x40,
        };
    }
};

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

const dmg_colors = [4]Pixel{
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
        dmg_palette: u1,
        /// Horizontally mirror the object.
        x_flip: bool,
        /// Vertically mirror the object.
        y_flip: bool,
        /// Whether the object is above or below the background and window.
        priority: ObjectPriority,
    },

    /// We want the smaller x position to win.
    fn lessThan(_: void, lhs: @This(), rhs: @This()) bool {
        return lhs.x_pos < rhs.x_pos;
    }
};

/// Whether the object is above or below the background and window.
pub const ObjectPriority = enum(u1) { above = 0, below = 1 };

/// Same as the `BackgroundPalette` except 0 is unused since it's transparent.
pub const ObjectPalette = packed struct(u8) {
    _: u2 = 0,
    id1: u2,
    id2: u2,
    id3: u2,
};

/// (CGB only) Color palette specification/index for background and objects.
pub const ColorPaletteIndex = packed struct(u8) {
    /// Used to address a byte in the background palette RAM.
    addr: u6,
    _: u1 = 1,
    /// Whether to increment the `addr` field after writing to `bcpd`/`ocpd`.
    auto_increment: bool,
};

/// (CGB only) Background/Window color palette data stored as RGB555.
pub const ColorPaletteData = packed struct(u16) {
    red: u5,
    blue: u5,
    green: u5,
    _: u1 = 0,

    fn to_pixel(self: @This()) Pixel {
        return Pixel{
            .r = @as(u8, self.red) << 3 | self.red >> 2,
            .g = @as(u8, self.blue) << 3 | self.blue >> 2,
            .b = @as(u8, self.green) << 3 | self.green >> 2,
            .a = math.maxInt(u8),
        };
    }
};

/// (CGB only) Attributes for the corresponding tile-number map entry in VRAM bank 0.
const TileAttributes = packed struct(u8) {
    /// Which of BGP 0-7 to use.
    palette: u3,
    /// Which bank to fetch the tile from.
    bank: u1,
    _: u1 = 0,
    /// Horizontally mirror the tile.
    x_flip: bool,
    /// Vertically mirror the tile.
    y_flip: bool,
    /// Whether color indices 1-3 of the background/window are drawn over objects.
    priority: bool,

    fn default() @This() {
        return @This(){
            .palette = 0,
            .bank = 0,
            .x_flip = false,
            .y_flip = false,
            .priority = false,
        };
    }
};

/// Execute a single step of the ppu.
pub fn step(gb: *gameboy.State) void {
    // ppu is not impacted by double speed mode
    gb.ppu.dots += gb.timer.pending_cycles / gb.speedMultiplier();

    switch (gb.memory.io.stat.mode) {
        .oam_scan => {
            if (gb.ppu.dots >= 80) {
                gb.ppu.dots = 0;
                gb.memory.io.stat.mode = .vram_read;
            }
        },
        .vram_read => {
            if (gb.ppu.dots >= 172) {
                gb.ppu.dots = 0;
                gb.memory.io.stat.mode = .h_blank;

                if (gb.memory.io.stat.h_blank_int_select) {
                    gb.memory.io.intf.lcd = true;
                }

                renderLine(gb);
            }
        },
        .h_blank => {
            if (gb.ppu.dots >= 204) {
                gb.ppu.dots = 0;
                gb.memory.io.ly += 1;

                gb.memory.io.stat.lyc_eq = gb.memory.io.ly == gb.memory.io.lyc;
                if (gb.memory.io.stat.lyc_int_select and gb.memory.io.stat.lyc_eq) {
                    gb.memory.io.intf.lcd = true;
                }

                if (gb.memory.io.ly == SCREEN_HEIGHT) {
                    gb.memory.io.stat.mode = .v_blank;
                    gb.memory.io.intf.v_blank = true;

                    if (gb.memory.io.stat.v_blank_int_select) {
                        gb.memory.io.intf.lcd = true;
                    }

                    @memcpy(gb.ppu.front_pixels, gb.ppu.back_pixels);
                } else {
                    gb.memory.io.stat.mode = .oam_scan;

                    if (gb.memory.io.stat.oam_scan_int_select) {
                        gb.memory.io.intf.lcd = true;
                    }
                }
            }
        },
        .v_blank => {
            if (gb.ppu.dots >= 456) {
                gb.ppu.dots = 0;
                gb.memory.io.ly += 1;

                gb.memory.io.stat.lyc_eq = gb.memory.io.ly == gb.memory.io.lyc;
                if (gb.memory.io.stat.lyc_int_select and gb.memory.io.stat.lyc_eq) {
                    gb.memory.io.intf.lcd = true;
                }

                if (gb.memory.io.ly > 153) {
                    gb.memory.io.stat.mode = .oam_scan;
                    gb.memory.io.ly = 0;
                    gb.ppu.window_line = 0;

                    gb.memory.io.stat.lyc_eq = gb.memory.io.ly == gb.memory.io.lyc;
                    if (gb.memory.io.stat.lyc_int_select and gb.memory.io.stat.lyc_eq) {
                        gb.memory.io.intf.lcd = true;
                    }
                    if (gb.memory.io.stat.oam_scan_int_select) {
                        gb.memory.io.intf.lcd = true;
                    }
                }
            }
        },
    }
}

/// Renders a single line to the pixel output buffer by reading vram and oam.
fn renderLine(gb: *gameboy.State) void {
    if (!gb.memory.io.lcdc.lcd_enable) return;

    var rendered_window = false;
    const LinePixel = struct {
        palette_id: u2,
        cgb_palette: u3,
        dmg_palette: u1,
        cgb_priority: bool,
        kind: enum(u1) { background, object },
    };
    var line = [_]LinePixel{.{
        .palette_id = 0,
        .cgb_palette = 0,
        .dmg_palette = 0,
        .cgb_priority = false,
        .kind = .background,
    }} ** SCREEN_WIDTH;

    if (gb.memory.io.key0 == .cgb or gb.memory.io.lcdc.bg_window_enable_priority) {
        const data_area_start: memory.Addr = switch (gb.memory.io.lcdc.bg_window_tile_data_area) {
            .signed => memory.TILE_BLOCK2_START,
            .unsigned => memory.TILE_BLOCK0_START,
        };

        for (0..SCREEN_WIDTH) |x_pixel_off| {
            // get the current tile based on if we're drawing the background or window
            const tile_map_start_selector, const tile_map_y, const tile_map_x =
                if (gb.memory.io.lcdc.window_enable and
                gb.memory.io.wy <= gb.memory.io.ly and
                gb.memory.io.wx -| 7 <= x_pixel_off) value: {
                    rendered_window = true;
                    break :value .{
                        gb.memory.io.lcdc.window_tile_map_area,
                        gb.ppu.window_line,
                        @as(u8, @intCast(x_pixel_off)) + 7 - gb.memory.io.wx,
                    };
                } else .{
                    gb.memory.io.lcdc.bg_tile_map_area,
                    gb.memory.io.ly +% gb.memory.io.scy,
                    @as(u8, @intCast(x_pixel_off)) +% gb.memory.io.scx,
                };
            const tile_map_start: memory.Addr = switch (tile_map_start_selector) {
                0 => memory.TILE_MAP0_START,
                1 => memory.TILE_MAP1_START,
            };

            const tile_map_addr: memory.Addr = tile_map_start +
                (@as(u16, tile_map_y) / 8) * 32 +
                (tile_map_x / 8);
            const tile_id = memory.read_vram(gb, tile_map_addr, 0);
            const tile_attrs: TileAttributes = switch (gb.memory.io.key0) {
                .cgb => @bitCast(memory.read_vram(gb, tile_map_addr, 1)),
                .dmg => TileAttributes.default(),
            };

            var tile_addr = switch (gb.memory.io.lcdc.bg_window_tile_data_area) {
                .signed => value: {
                    const offset = @as(i8, @bitCast(tile_id)) * @as(i16, 16);
                    break :value if (offset < 0)
                        data_area_start - @abs(offset)
                    else
                        data_area_start + @abs(offset);
                },
                .unsigned => data_area_start + @as(u16, tile_id) * 16,
            };
            tile_addr += 2 * if (tile_attrs.y_flip) 7 - (tile_map_y % 8) else (tile_map_y % 8);

            // each tile is 16 bytes, and the pixel is spread across both bytes
            const tile_data1 = memory.read_vram(gb, tile_addr, tile_attrs.bank);
            const tile_data2 = memory.read_vram(gb, tile_addr + 1, tile_attrs.bank);

            const x_bit_num: u3 = if (tile_attrs.x_flip)
                7 - @as(u3, @intCast(tile_map_x % 8))
            else
                @intCast(tile_map_x % 8);
            const lo = tile_data1 & (@as(u8, 0x80) >> x_bit_num) != 0;
            const hi = tile_data2 & (@as(u8, 0x80) >> x_bit_num) != 0;

            // use the palette to find the final color
            const palette_id = @as(u2, @intFromBool(hi)) << 1 | @intFromBool(lo);
            line[x_pixel_off] = .{
                .palette_id = palette_id,
                .cgb_palette = tile_attrs.palette,
                .dmg_palette = undefined,
                .cgb_priority = tile_attrs.priority,
                .kind = .background,
            };
        }
    }
    if (rendered_window) {
        // only increment the window line if we actually rendered it
        gb.ppu.window_line += 1;
    }

    if (gb.memory.io.lcdc.obj_enable) {
        var obj_addr: memory.Addr = memory.OAM_START;
        const obj_size = @sizeOf(Object);
        const obj_height: u5 = switch (gb.memory.io.lcdc.obj_size) {
            .bit8 => 8,
            .bit16 => 16,
        };

        // draw at most 10 objects
        var visible_objects: [10]Object = [_]Object{@bitCast(@as(u32, 0))} ** 10;
        var visible_object_idx: u8 = 0;

        while (obj_addr < memory.OAM_START + 0xa0) : (obj_addr += obj_size) {
            // get the current oam object
            const rel_addr = obj_addr - memory.OAM_START;
            const object: Object = @bitCast(
                gb.memory.oam[rel_addr .. rel_addr + obj_size][0..obj_size].*,
            );

            if (object.x_pos != 0 and
                object.y_pos <= gb.memory.io.ly + 16 and
                gb.memory.io.ly + 16 < object.y_pos + obj_height)
            {
                visible_objects[visible_object_idx] = object;
                visible_object_idx += 1;

                if (visible_object_idx == visible_objects.len) {
                    break;
                }
            }
        }

        // in DMG only the object with the smallest x position wins, otherwise
        // it is decided by the order in the oam
        if (gb.memory.io.opri == .dmg) {
            mem.sort(Object, &visible_objects, {}, Object.lessThan);
        }

        // first we need to pick the first non-transparent object pixels
        const ObjectPixel = struct {
            palette_id: u2,
            cgb_palette: u3,
            dmg_palette: u1,
            priority: ObjectPriority,
        };
        var object_line = [_]ObjectPixel{.{
            .palette_id = 0,
            .cgb_palette = 0,
            .dmg_palette = 0,
            .priority = .below,
        }} ** SCREEN_WIDTH;
        for (visible_objects) |object| {
            const tile_id = switch (gb.memory.io.lcdc.obj_size) {
                .bit8 => object.tile_id,
                .bit16 => object.tile_id & 0xfe,
            };

            for (0..8) |x_pixel_off| {
                const x_pixel: u8 = object.x_pos +% @as(u8, @intCast(x_pixel_off)) -% 8;

                if (x_pixel < SCREEN_WIDTH and object_line[x_pixel].palette_id == 0) {
                    // always used unsigned addressing for objects
                    var tile_addr = memory.TILE_BLOCK0_START + @as(u16, tile_id) * 16;

                    const y_pixel_off = gb.memory.io.ly + 16 - object.y_pos;
                    tile_addr += (if (object.flags.y_flip)
                        obj_height - 1 - y_pixel_off
                    else
                        y_pixel_off) * 2;

                    const bank = switch (gb.memory.io.key0) {
                        .cgb => object.flags.bank,
                        .dmg => 0,
                    };
                    const tile_data1 = memory.read_vram(gb, tile_addr, bank);
                    const tile_data2 = memory.read_vram(gb, tile_addr + 1, bank);

                    const x_bit_num: u3 = if (object.flags.x_flip)
                        @intCast(7 - x_pixel_off)
                    else
                        @intCast(x_pixel_off);
                    const lo = tile_data1 & (@as(u8, 0x80) >> x_bit_num) != 0;
                    const hi = tile_data2 & (@as(u8, 0x80) >> x_bit_num) != 0;

                    const palette_id = @as(u2, @intFromBool(hi)) << 1 | @intFromBool(lo);
                    object_line[x_pixel] = .{
                        .palette_id = palette_id,
                        .cgb_palette = object.flags.cgb_palette,
                        .dmg_palette = object.flags.dmg_palette,
                        .priority = object.flags.priority,
                    };
                }
            }
        }

        // next we mix the object and background pixels based on their priority
        for (0..SCREEN_WIDTH) |x_pixel_off| {
            // if the object pixel is transparent, skip it
            if (object_line[x_pixel_off].palette_id == 0) continue;

            const obj_has_priority = switch (gb.memory.io.key0) {
                .cgb => line[x_pixel_off].palette_id == 0 or
                    !gb.memory.io.lcdc.bg_window_enable_priority or
                    (!line[x_pixel_off].cgb_priority and object_line[x_pixel_off].priority == .above),
                .dmg => line[x_pixel_off].palette_id == 0 or
                    (line[x_pixel_off].kind == .background and object_line[x_pixel_off].priority == .above),
            };
            if (obj_has_priority) {
                line[x_pixel_off] = .{
                    .palette_id = object_line[x_pixel_off].palette_id,
                    .cgb_palette = object_line[x_pixel_off].cgb_palette,
                    .dmg_palette = object_line[x_pixel_off].dmg_palette,
                    .cgb_priority = undefined,
                    .kind = .object,
                };
            }
        }
    }

    for (0..SCREEN_WIDTH) |x_pixel_off| {
        const palette_id = line[x_pixel_off].palette_id;
        const color = switch (gb.memory.io.key0) {
            .cgb => value: {
                const color_data_size = @sizeOf(ColorPaletteData);
                const color_offset: u7 =
                    @as(u6, line[x_pixel_off].cgb_palette) * 4 * color_data_size +
                    @as(u6, palette_id) * color_data_size;
                const color_ram = switch (line[x_pixel_off].kind) {
                    .background => gb.ppu.bg_color_ram,
                    .object => gb.ppu.obj_color_ram,
                };
                const color_data: ColorPaletteData = @bitCast(
                    color_ram[color_offset .. color_offset + color_data_size][0..color_data_size].*,
                );
                break :value color_data.to_pixel();
            },
            .dmg => value: {
                const color_id = switch (line[x_pixel_off].kind) {
                    .background => switch (palette_id) {
                        0 => gb.memory.io.bgp.id0,
                        1 => gb.memory.io.bgp.id1,
                        2 => gb.memory.io.bgp.id2,
                        3 => gb.memory.io.bgp.id3,
                    },
                    .object => id_value: {
                        const palette = switch (line[x_pixel_off].dmg_palette) {
                            0 => gb.memory.io.obp0,
                            1 => gb.memory.io.obp1,
                        };
                        const color_id = switch (palette_id) {
                            // if the object's palette id was 0, we would use the background instead
                            0 => unreachable,
                            1 => palette.id1,
                            2 => palette.id2,
                            3 => palette.id3,
                        };
                        break :id_value color_id;
                    },
                };
                break :value dmg_colors[color_id];
            },
        };

        gb.ppu.back_pixels[@as(u16, gb.memory.io.ly) * SCREEN_WIDTH + x_pixel_off] = color;
    }
}
