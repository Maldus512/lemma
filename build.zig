const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const allocator = std.heap.page_allocator;

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const custom_llvm_path = b.option([]const u8, "llvm_path", "Path to custom LLVM installation");
    const custom_libstdcpp_path = b.option([]const u8, "libstdcpp_path", "Path to custom libstdc++.a library");

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // Creates a step for unit testing.
    const tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "test.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    if (custom_llvm_path orelse env.get("LEMMA_LLVM_PATH")) |path| {
        const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ path, "lib" });
        defer allocator.free(lib_path);
        tests.addLibraryPath(.{ .cwd_relative = lib_path });

        const include_path = try std.fs.path.join(allocator, &[_][]const u8{ path, "include" });
        defer allocator.free(include_path);
        tests.addIncludePath(.{ .cwd_relative = include_path });
    }

    var llvm_libs = std.ArrayList([]const u8).init(allocator);
    defer {
        for (llvm_libs.items) |string| {
            allocator.free(string);
        }
        llvm_libs.deinit();
    }

    const llvm_config_output = b.run(&[_][]const u8{ "llvm-config", "--libs", "core", "executionengine", "interpreter", "analysis", "native", "bitwriter" });
    var it = std.mem.splitSequence(u8, llvm_config_output, " ");
    while (it.next()) |libflag| {
        const no_newline = try std.mem.replaceOwned(u8, allocator, libflag, "\n", "");
        defer allocator.free(no_newline);

        try llvm_libs.insert(0, try std.mem.replaceOwned(u8, allocator, no_newline, "-l", ""));
    }

    for (llvm_libs.items) |llvm_lib| {
        tests.linkSystemLibrary(llvm_lib);
    }

    tests.linkSystemLibrary("rt");
    tests.linkSystemLibrary("dl");
    tests.linkSystemLibrary("m");
    tests.linkSystemLibrary("z");
    tests.linkSystemLibrary("zstd");
    tests.linkSystemLibrary("xml2");
    tests.linkSystemLibrary("pthread");

    if (custom_libstdcpp_path orelse env.get("LEMMA_LIBSTDCPP_PATH")) |path| {
        tests.addObjectFile(.{ .cwd_relative = path });
    }

    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
    const ins_lib_unit_tests = b.addInstallArtifact(tests, .{});
    test_step.dependOn(&ins_lib_unit_tests.step);
}
