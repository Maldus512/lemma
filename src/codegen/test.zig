const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const imports = .{
    .codegen = @import("codegen.zig"),
    .sema = @import("../sema/sema.zig"),
};

test "Simple expression" {
    const allocator = testing.allocator;

    const source = "1+2";
    var sema_result = try imports.sema.analyze(allocator, source);
    defer sema_result.deinit();

    var compiled = try imports.codegen.compile(allocator, sema_result);
    defer compiled.deinit();
    var llvm_ir = try compiled.module.printToString();
    defer llvm_ir.deinit();

    try testing.expectEqual(try compiled.execute(), 3);
}

test "Main function" {
    const allocator = testing.allocator;

    const source = "fn argc argv => 1+2";
    var sema_result = try imports.sema.analyze(allocator, source);
    defer sema_result.deinit();

    //const compiled = try imports.codegen.compile(allocator, sema_result);
    //defer compiled.deinit();
    //const llvm_ir = try compiled.module.printToString();
    //defer llvm_ir.deinit();

    //std.log.warn("{s}\n", .{llvm_ir.message});

    //try testing.expectEqual(try compiled.execute(), 3);
    //std.log.warn("> {}\n", .{try compiled.execute()});
}
