const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const imports = .{
    .parser = @import("parser.zig"),
    .ast = @import("ast.zig"),
};

const AstNode = imports.ast.Node;
const AstNodeIndex = imports.ast.NodeIndex;
const ParseResult = imports.parser.ParseResult;

test "Arithmetic" {
    const allocator = std.heap.page_allocator;

    {
        const single_number = "1";
        const result = try imports.parser.parse(allocator, single_number);

        try expectAstBranch(&result, result.root, &.{.{ .number, "1", null }});
    }

    {
        const sum = "1+2";
        const result = try imports.parser.parse(allocator, sum);

        try expectAstBranch(&result, result.root, &.{ .{ .operation, "+", "lhs" }, .{ .number, "1", null } });

        try expectAstBranch(&result, result.root, &.{ .{ .operation, "+", "rhs" }, .{ .number, "2", null } });
    }

    {
        const sum = "1+2*3-4/5";
        const result = try imports.parser.parse(allocator, sum);

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "-", "lhs" },
            .{ .operation, "+", "lhs" },
            .{ .number, "1", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "-", "lhs" },
            .{ .operation, "+", "rhs" },
            .{ .operation, "*", "lhs" },
            .{ .number, "2", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "-", "lhs" },
            .{ .operation, "+", "rhs" },
            .{ .operation, "*", "rhs" },
            .{ .number, "3", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "-", "rhs" },
            .{ .operation, "/", "lhs" },
            .{ .number, "4", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "-", "rhs" },
            .{ .operation, "/", "rhs" },
            .{ .number, "5", null },
        });
    }

    {
        const sum = "(1+2)*((3-4)/5)";
        const result = try imports.parser.parse(allocator, sum);

        // 1
        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "lhs" },
            .{ .operation, "+", "lhs" },
            .{ .number, "1", null },
        });

        // 2
        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "lhs" },
            .{ .operation, "+", "rhs" },
            .{ .number, "2", null },
        });

        // 3
        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "rhs" },
            .{ .operation, "/", "lhs" },
            .{ .operation, "-", "lhs" },
            .{ .number, "3", null },
        });

        // 4
        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "rhs" },
            .{ .operation, "/", "lhs" },
            .{ .operation, "-", "rhs" },
            .{ .number, "4", null },
        });

        // 5
        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "rhs" },
            .{ .operation, "/", "rhs" },
            .{ .number, "5", null },
        });
    }
}

fn expectAstBranch(result: *const ParseResult, node_index: AstNodeIndex, comptime path: []const std.meta.Tuple(&.{ AstNode.Tag, []const u8, ?[]const u8 })) !void {
    var cursor = node_index;
    const Branches = enum { lhs, rhs };

    for (path) |branch| {
        const node = result.getNode(cursor);

        try testing.expectEqual(node.tag, branch[0]);

        if (branch[1].len > 0) {
            try testing.expectEqualStrings(branch[1], result.getSourceSlice(cursor));
        }

        if (branch[2]) |field| {
            switch (node.tag) {
                .operation => {
                    const next = std.meta.stringToEnum(Branches, field) orelse unreachable;

                    cursor = switch (next) {
                        .lhs => node.data.operation.lhs,
                        .rhs => node.data.operation.rhs,
                    };
                },
                else => {},
            }
        }
    }
}

test "Functions" {
    const allocator = std.heap.page_allocator;

    {
        const identity = "fn x => x";
        const result = try imports.parser.parse(allocator, identity);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 1);
        try testing.expectEqualStrings(result.getSourceSlice(root.data.function.arguments.items[0]), "x");

        const body = result.getNode(root.data.function.body);
        try testing.expectEqual(body.tag, .identifier);
        try testing.expectEqualStrings(result.getSourceSlice(root.data.function.body), "x");
    }

    {
        const sum = "fn x y => x + y";
        const result = try imports.parser.parse(allocator, sum);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 2);
        try testing.expectEqualStrings(result.getSourceSlice(root.data.function.arguments.items[0]), "x");
        try testing.expectEqualStrings(result.getSourceSlice(root.data.function.arguments.items[1]), "y");

        try expectAstBranch(&result, root.data.function.body, &.{
            .{ .operation, "+", "lhs" },
            .{ .identifier, "x", null },
        });
        try expectAstBranch(&result, root.data.function.body, &.{
            .{ .operation, "+", "rhs" },
            .{ .identifier, "y", null },
        });
    }
}

test "Applications" {
    const allocator = std.heap.page_allocator;

    {
        const self_application = "x y";
        const result = try imports.parser.parse(allocator, self_application);

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "lhs" },
            .{ .identifier, "x", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "rhs" },
            .{ .identifier, "y", null },
        });
    }

    {
        const self_application = "foo x y z";
        const result = try imports.parser.parse(allocator, self_application);

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .identifier, "foo", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .operation, "", "rhs" },
            .{ .identifier, "x", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "lhs" },
            .{ .operation, "", "rhs" },
            .{ .identifier, "y", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "", "rhs" },
            .{ .identifier, "z", null },
        });
    }

    {
        const mixed_application = "foo x y * 2";
        const result = try imports.parser.parse(allocator, mixed_application);

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .identifier, "foo", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "lhs" },
            .{ .operation, "", "lhs" },
            .{ .operation, "", "rhs" },
            .{ .identifier, "x", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "lhs" },
            .{ .operation, "", "rhs" },
            .{ .identifier, "y", null },
        });

        try expectAstBranch(&result, result.root, &.{
            .{ .operation, "*", "rhs" },
            .{ .number, "2", null },
        });
    }
}

test "Let In" {
    const allocator = std.heap.page_allocator;

    {
        const identity = "let x in x";
        const result = try imports.parser.parse(allocator, identity);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .letin);
    }
}
