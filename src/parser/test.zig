const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const imports = .{
    .parser = @import("parser.zig"),
};

const AstNode = imports.parser.AstNode;
const AstNodeTag = imports.parser.AstNodeTag;

test "Arithmetic" {
    const allocator = std.heap.page_allocator;

    {
        const single_number = "1";
        const result = try imports.parser.parse(allocator, single_number);
        try testing.expect(result.ast.is(AstNodeTag.number));
        try testing.expect(result.ast.number == 1);
    }

    {
        const sum = "1+2";
        const result = try imports.parser.parse(allocator, sum);
        try testing.expect(result.ast.is(AstNodeTag.operation));

        const first_value = result.ast.operation.lhs.number;
        try testing.expect(first_value == 1);

        const second_value = result.ast.operation.rhs.number;
        try testing.expect(second_value == 2);
    }

    {
        const sum = "1+2*3-4/5";
        const result = try imports.parser.parse(allocator, sum);

        try testing.expect(result.ast.is(.operation));
        try testing.expectEqual(result.ast.operation.operator, .subtraction);

        try testing.expect(result.ast.operation.lhs.is(.operation));
        try testing.expectEqual(result.ast.operation.lhs.operation.operator, .sum);

        try testing.expect(result.ast.operation.lhs.operation.lhs.is(.number));
        try testing.expectEqual(result.ast.operation.lhs.operation.lhs.number, 1);

        try testing.expect(result.ast.operation.lhs.operation.rhs.is(.operation));
        try testing.expectEqual(result.ast.operation.lhs.operation.rhs.operation.operator, .multiplication);

        try testing.expect(result.ast.operation.lhs.operation.rhs.operation.lhs.is(.number));
        try testing.expectEqual(result.ast.operation.lhs.operation.rhs.operation.lhs.number, 2);

        try testing.expect(result.ast.operation.lhs.operation.rhs.operation.rhs.is(.number));
        try testing.expectEqual(result.ast.operation.lhs.operation.rhs.operation.rhs.number, 3);

        try testing.expect(result.ast.operation.rhs.is(.operation));
        try testing.expectEqual(result.ast.operation.rhs.operation.operator, .division);

        try testing.expect(result.ast.operation.rhs.operation.lhs.is(.number));
        try testing.expectEqual(result.ast.operation.rhs.operation.lhs.number, 4);

        try testing.expect(result.ast.operation.rhs.operation.rhs.is(.number));
        try testing.expectEqual(result.ast.operation.rhs.operation.rhs.number, 5);
    }
}
