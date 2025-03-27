const std = @import("std");

pub fn build(b: *std.Build) void {
    // build the wasm executable
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zgbc",
        .root_module = exe_mod,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);

    // run tests on host
    const host_target = b.standardTargetOptions(.{});
    const test_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .root_module = test_lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
