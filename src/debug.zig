extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;
extern "env" fn consoleLogJson(ptr: [*]const u8, len: usize) void;
extern "env" fn consoleLogJsonDiff(oldPtr: [*]const u8, oldLen: usize, newPtr: [*]const u8, newLen: usize) void;

const std = @import("std");
const allocator = std.heap.wasm_allocator;

pub fn print(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(allocator, fmt, args) catch return;
    defer allocator.free(msg);
    consoleLog(msg.ptr, msg.len);
}

const stringifyOptions = std.json.StringifyOptions{ .emit_strings_as_arrays = true };

pub fn printJson(value: anytype) void {
    const json = std.json.stringifyAlloc(allocator, value, stringifyOptions) catch return;
    defer allocator.free(json);
    consoleLogJson(json.ptr, json.len);
}

pub fn printJsonDiff(old: anytype, new: anytype) void {
    const oldJson = std.json.stringifyAlloc(allocator, old, stringifyOptions) catch return;
    defer allocator.free(oldJson);

    const newJson = std.json.stringifyAlloc(allocator, new, stringifyOptions) catch return;
    defer allocator.free(newJson);

    consoleLogJsonDiff(oldJson.ptr, oldJson.len, newJson.ptr, newJson.len);
}
