const std = @import("std");
const testing = std.testing;

const imports = .{
    .lexer = @import("lexer.zig"),
};

const Token = imports.lexer.Token;

test "Identifiers" {
    const ids = [_][]const u8{ "variable_name", "_zebborbio" };
    for (ids) |id| {
        try checkToken(id, .identifier);
    }
}

test "Atoms" {
    const allocator = testing.allocator;
    const atoms = [_][]const u8{ "Banana", "Zebborbio" };
    for (atoms) |atom| {
        const atom_string = try std.fmt.allocPrint(allocator, "@{s}", .{atom});
        defer allocator.free(atom_string);
        try checkToken(atom_string, .atom);
    }
}

test "Numbers" {
    const numbers = [_][]const u8{ "42", "512" };
    for (numbers) |number| {
        try checkToken(number, .number);
    }
}

test "Keywords" {
    const ExpectedToken = struct {
        string: []const u8,
        tag: Token.Tag,

        fn new(string: []const u8, tag: Token.Tag) @This() {
            return @This(){ .string = string, .tag = tag };
        }
    };

    const expected_tokens = [_]ExpectedToken{
        ExpectedToken.new("fn", .lambda),
        ExpectedToken.new("match", .match),
        ExpectedToken.new("with", .with),
        ExpectedToken.new("if", .if_keyword),
        ExpectedToken.new("then", .then),
        ExpectedToken.new("else", .else_keyword),
        ExpectedToken.new("let", .let),
        ExpectedToken.new("in", .in),
        ExpectedToken.new("import", .import),
        ExpectedToken.new(";", .semicolon),
        ExpectedToken.new("=", .assign),
        ExpectedToken.new("(", .left_paren),
        ExpectedToken.new(")", .right_paren),
        ExpectedToken.new("[", .left_square_bracket),
        ExpectedToken.new("]", .right_square_bracket),
        ExpectedToken.new("{", .left_curly_brace),
        ExpectedToken.new("}", .right_curly_brace),
        ExpectedToken.new(",", .comma),
        ExpectedToken.new(":", .colon),
        ExpectedToken.new("->", .single_arrow),
        ExpectedToken.new("=>", .double_arrow),
        ExpectedToken.new("+", .plus),
        ExpectedToken.new("-", .minus),
        ExpectedToken.new("/", .slash),
        ExpectedToken.new("*", .star),
        ExpectedToken.new("|>", .pipe),
    };

    const allocator = testing.allocator;
    var source_string: []u8 = "";
    var positions = std.ArrayList(std.meta.Tuple(&.{ usize, usize })){};
    defer positions.deinit(allocator);

    for (expected_tokens) |expected_token| {
        // Isolated test
        try checkToken(expected_token.string, expected_token.tag);

        const new_string = try std.fmt.allocPrint(allocator, "{s} {s}", .{ source_string, expected_token.string });

        try positions.append(allocator, .{ source_string.len + 1, source_string.len + 1 + expected_token.string.len });

        allocator.free(source_string);
        source_string = new_string;
    }
    defer allocator.free(source_string);

    var result = try imports.lexer.scan(allocator, source_string);
    defer result.deinit();

    try testing.expectEqual(expected_tokens.len, result.tokens.items.len);

    for (expected_tokens, 0..) |expected_token, index| {
        const token_index: u32 = @intCast(index);
        const found = result.getToken(token_index) orelse {
            try testing.expect(false);
            unreachable;
        };
        const expected_position = positions.items[index];

        const begin = found.getStartingIndex(source_string);

        try testing.expectEqual(expected_token.tag, found.tag);
        try testing.expectEqual(expected_position[0], begin);
        try testing.expectEqual(expected_position[1], begin + found.size());
    }
}

fn checkToken(source: []const u8, tag: Token.Tag) !void {
    var scan_result = try imports.lexer.scan(testing.allocator, source);
    defer scan_result.deinit();
    try testing.expect(scan_result.tokens.items.len == 1);

    if (scan_result.getToken(0)) |found| {
        if (found.tag != tag) {
            std.debug.print("\nExpected {any}, found {any}\n", .{ tag, found.tag });
            try testing.expect(false);
        }
        try testing.expect(std.mem.eql(u8, source, found.source_span));
    } else {
        std.debug.print("\nToken {any} not found in \"{s}\"", .{ tag, source });
        try testing.expect(false);
    }
}
