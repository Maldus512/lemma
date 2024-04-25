const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const imports = .{
    .irt = @import("irt.zig"),
    .sema = @import("sema.zig"),
};

const ItNode = imports.irt.Node;
const SemaResult = imports.sema.Result;

test "Values" {
    const allocator = std.heap.page_allocator;

    {
        const source = "1";
        const result = try imports.sema.analyze(allocator, source);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .number);
        try testing.expectEqual(root.data.number, 1);

        try testing.expectEqualStrings("Num", try result.displayType(allocator, result.root));
    }
}

test "MergeFindSet" {}

test "Identifiers" {
    const allocator = std.heap.page_allocator;

    {
        const source = "x";
        const result = try imports.sema.analyze(allocator, source);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .freeIdentifier);
        try testing.expectEqualStrings(try result.displayType(allocator, result.getNodeTypeIndex(result.root)), "BOTTOM"); // It's a free identifier, it has an invalid type
    }

    {
        const source = "fn x => x";
        const result = try imports.sema.analyze(allocator, source);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 1);
        try testing.expectEqual(result.getNode(root.data.function.body).tag, .boundIdentifier);

        try testing.expectEqualStrings(try result.displayType(allocator, result.getNodeTypeIndex(result.root)), "a->a");
    }

    {
        const source = "fn x y => x";
        const result = try imports.sema.analyze(allocator, source);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 2);
        try testing.expectEqual(result.getNode(root.data.function.body).tag, .boundIdentifier);

        try testing.expectEqualStrings(try result.displayType(allocator, result.getNodeTypeIndex(result.root)), "a->b->a");
    }
}

test "Application" {
    const allocator = std.heap.page_allocator;

    {
        const source = "foo x y z";
        const result = try imports.sema.analyze(allocator, source);

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .application);
        try testing.expectEqual(root.data.application.arguments.items.len, 3);
    }
}

test "Type inference" {
    const allocator = std.heap.page_allocator;

    {
        std.log.warn("Simple arrow\n", .{});
        const source = "fn x y => x y";
        const result = try imports.sema.analyze(allocator, source);

        try testing.expectEqualStrings("(b->c)->b->c", try result.displayType(allocator, result.getNodeTypeIndex(result.root)));
    }

    {
        const source = "fn x y z => x y z";
        std.log.warn("Complex foo\n", .{});
        const result = try imports.sema.analyze(allocator, source);

        //try testing.expectEqualStrings(try result.displayType(allocator, result.getNodeTypeIndex(result.root)), "a->b->c->d->e");

        std.log.warn("{s}\n", .{try result.displayType(allocator, result.getNodeTypeIndex(result.root))});
        for (result.constraints.items) |constraint| {
            std.log.warn("{s} = {s}\n", .{ try result.displayType(allocator, constraint[0]), try result.displayType(allocator, constraint[1]) });
        }
    }
}
