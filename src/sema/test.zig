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
    const allocator = testing.allocator;

    {
        const source = "1";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .number);
        try testing.expectEqual(root.data.number, 1);

        const string = try result.displayType(allocator, result.root);
        defer allocator.free(string);
        try testing.expectEqualStrings("Num", string);
    }
}

test "MergeFindSet" {}

test "Identifiers" {
    const allocator = testing.allocator;

    {
        const source = "x";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .freeIdentifier);

        const string = try result.displayType(allocator, result.getNodeTypeIndex(result.root));
        defer allocator.free(string);

        try testing.expectEqualStrings(string, "BOTTOM"); // It's a free identifier, it has an invalid type
    }

    {
        const source = "fn x => x";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 1);
        try testing.expectEqual(result.getNode(root.data.function.body).tag, .boundIdentifier);

        const string = try result.displayType(allocator, result.getNodeTypeIndex(result.root));
        defer allocator.free(string);

        try testing.expectEqualStrings(string, "a->a");
    }

    {
        const source = "fn x y => x";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .function);
        try testing.expectEqual(root.data.function.arguments.items.len, 2);
        try testing.expectEqual(result.getNode(root.data.function.body).tag, .boundIdentifier);

        const string = try result.displayType(allocator, result.getNodeTypeIndex(result.root));
        defer allocator.free(string);

        try testing.expectEqualStrings(string, "a->b->a");
    }
}

test "Application" {
    const allocator = testing.allocator;

    {
        const source = "foo x y z";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const root = result.getRoot();
        try testing.expectEqual(root.tag, .application);
        try testing.expectEqual(root.data.application.arguments.items.len, 3);
    }
}

test "Type inference" {
    const allocator = testing.allocator;

    {
        const source = "fn x y => x y";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const string = try result.displayType(allocator, result.getNodeTypeIndex(result.root));
        defer allocator.free(string);

        try testing.expectEqualStrings("(b->c)->b->c", string);
    }

    {
        const source = "fn x y z => x y z";
        const result = try imports.sema.analyze(allocator, source);
        defer result.deinit();

        const string = try result.displayType(allocator, result.getNodeTypeIndex(result.root));
        defer allocator.free(string);

        try testing.expectEqualStrings(string, "(b->c->e)->b->c->e");
    }
}
