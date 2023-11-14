const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const imports = .{
    .lexer = @import("lexer.zig"),
};

const Token = imports.lexer.Token;

test "Identifiers" {
    const ids = [_][]const u8{ "variable_name", "_zebborbio" };
    for (ids) |id| {
        try checkToken(id, try Token.newId(std.heap.page_allocator, id));
    }
}

test "Atoms" {
    const allocator = std.heap.page_allocator;
    const atoms = [_][]const u8{ "Banana", "Zebborbio" };
    for (atoms) |atom| {
        const atom_string = try std.fmt.allocPrint(allocator, "@{s}", .{atom});
        defer allocator.free(atom_string);
        try checkToken(atom_string, try Token.newAtom(std.heap.page_allocator, atom));
    }
}

test "Numbers" {
    const numbers = [_][]const u8{ "42", "512" };
    for (numbers) |number| {
        try checkToken(number, try Token.newNumber(std.heap.page_allocator, number));
    }
}

test "Keywords" {
    const ExpectedToken = struct {
        string: []const u8,
        token: Token,

        fn new(string: []const u8, token: Token) @This() {
            return @This(){ .string = string, .token = token };
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

    const allocator = std.heap.page_allocator;
    var total_string: []u8 = "";
    var positions = std.ArrayList(std.meta.Tuple(&.{ usize, usize })).init(allocator);
    defer positions.deinit();

    for (expected_tokens) |expected_token| {
        // Isolated test
        try checkToken(expected_token.string, expected_token.token);

        const new_string = try std.fmt.allocPrint(allocator, "{s} {s}", .{ total_string, expected_token.string });

        try positions.append(.{ total_string.len + 1, total_string.len + 1 + expected_token.string.len });

        allocator.free(total_string);
        total_string = new_string;
    }

    const result = try imports.lexer.scan(std.heap.page_allocator, total_string);

    try testing.expectEqual(expected_tokens.len, result.tokens.items.len);

    for (expected_tokens, 0..) |expected_token, index| {
        const token_index = @intCast(u32, index);
        const found = result.getToken(token_index) orelse {
            try testing.expect(false);
            unreachable;
        };
        const span = result.getTokenPosition(token_index) orelse {
            try testing.expect(false);
            unreachable;
        };
        const expected_position = positions.items[index];

        try testing.expect(expected_token.token.equal(found));
        try testing.expectEqual(expected_position[0], span.begin);
        try testing.expectEqual(expected_position[1], span.end);
    }
}

fn checkToken(source: []const u8, token: Token) !void {
    var scan_result = try imports.lexer.scan(std.heap.page_allocator, source);
    try testing.expect(scan_result.tokens.items.len == 1);

    if (scan_result.getToken(0)) |found| {
        if (!found.equal(token)) {
            std.debug.print("\nExpected {any}, found {any}\n", .{ token, found });
            try testing.expect(false);
        }
    } else {
        std.debug.print("\nToken {any} not found in \"{s}\"", .{ token, source });
        try testing.expect(false);
    }
}
