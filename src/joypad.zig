const std = @import("std");
const testing = std.testing;

const gameboy = @import("gb.zig");

/// Tracks the state of which buttons are being pressed.
pub const ButtonState = packed union {
    nibbles: packed struct(u8) {
        d_pad: u4,
        buttons: u4,
    },
    named: packed struct(u8) {
        right: u1,
        left: u1,
        up: u1,
        down: u1,
        a: u1,
        b: u1,
        select: u1,
        start: u1,
    },

    pub fn jsonStringify(
        self: @This(),
        writer: anytype,
    ) !void {
        try writer.beginObject();

        inline for (@typeInfo(@This()).@"union".fields) |unionField| {
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

/// One of the possible buttons that can be pressed.
/// `u8` instead of `u3` since it needs to be extern compatible.
pub const Button = enum(u8) { right, left, up, down, a, b, select, start };

pub fn press(gb: *gameboy.State, button: Button) void {
    switch (button) {
        inline else => |b| @field(gb.button_state.named, @tagName(b)) = 0,
    }
    gb.io_registers.intf.joypad = true;
}

pub fn release(gb: *gameboy.State, button: Button) void {
    switch (button) {
        inline else => |b| @field(gb.button_state.named, @tagName(b)) = 1,
    }
}
