const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
    .ast = @import("ast.zig"),
};

pub const AstNodeTag = imports.ast.Node.Tag;

const String = std.ArrayList(u8);
const Allocator = std.mem.Allocator;
const SourceSpan = imports.common.meta.SourceSpan;
const ScanResult = imports.lexer.ScanResult;
const ScanResultIterator = imports.lexer.ScanResultIterator;
const AstNodeList = imports.ast.NodeList;
const AstNode = imports.ast.Node;
const Operator = imports.ast.Operator;
const Token = imports.lexer.Token;
const Value = imports.common.Value;
const TokenIndex = imports.lexer.TokenIndex;

const Error = error{ OutOfMemory, Overflow };

pub const ParseResult = struct {
    scan_result: ScanResult,
    ast: *AstNode,

    const Self = @This();

    pub fn getNumberValue(self: *const Self, node: *const AstNode) isize {
        switch (node.data) {
            .number => |token_index| {
                const token = self.scan_result.tokens.items[token_index];
                return std.fmt.parseInt(isize, token.source_span, 0) catch unreachable;
            },
            else => unreachable,
        }
    }

    pub fn getSourceSlice(self: *const Self, node: *const AstNode) []const u8 {
        const token = self.scan_result.tokens.items[node.token];
        return token.source_span;
    }
};

pub fn parse(gpa: Allocator, source: []const u8) !ParseResult {
    const scan_result = try imports.lexer.scan(gpa, source);

    var parser = Parser{ .gpa = gpa, .token_iterator = scan_result.intoIter() };

    return ParseResult{
        .scan_result = scan_result,
        .ast = try parser.parse(),
    };
}

const Parser = struct {
    //TODO: save errors in a list for ease of access
    gpa: Allocator,
    token_iterator: ScanResultIterator,

    const Self = @This();

    fn parse(self: *Self) !*AstNode {
        return self.parseExpression();
    }

    const BindingPower = std.meta.Tuple(&.{ u16, u16 });

    fn infix_binding_power(op: Operator) BindingPower {
        return switch (op) {
            .forwarding => .{ 1, 2 },
            .addition, .subtraction => .{ 3, 4 },
            .multiplication, .division => .{ 5, 6 },
            .application => .{ 7, 8 },
        };
    }

    fn parseExpression(self: *Self) Error!*AstNode {
        switch (self.token_iterator.peek(0).tag) {
            .lambda => return self.parseFunction(),
            else => return self.parseInfixExpression(0),
        }
    }

    fn parseFunction(self: *Self) Error!*AstNode {
        const index = self.token_iterator.at();

        if (self.expectToken(.lambda) == null) {
            return self.allocateInvalid(index, &.{.function}, &.{});
        }

        //TODO: polymorphic variables

        var arguments = AstNodeList.init(self.gpa);
        errdefer arguments.deinit();

        while (!self.atToken(.double_arrow)) {
            try arguments.append(try self.parsePattern());
        }

        if (self.expectToken(.double_arrow) == null) {
            defer arguments.deinit();
            return self.allocateInvalid(index, &.{.function}, arguments.items);
        }

        return self.allocateAstNode(AstNode{
            .token = index,
            .tag = .function,
            .data = .{
                .function = .{ .arguments = arguments, .body = try self.parseExpression() },
            },
        });
    }

    fn parsePattern(self: *Self) Error!*AstNode {
        const index = self.token_iterator.at();

        if (self.expectToken(.identifier)) |_| {
            return try self.allocateAstNode(AstNode{ .token = index, .tag = .pattern, .data = undefined });
        } else {
            return try self.allocateInvalid(index, &.{.pattern}, &.{});
        }
    }

    fn parseInfixExpression(self: *Self, min_bp: u16) Error!*AstNode {
        // Pratt parser

        var left_hand_side = try self.parseAtom();

        while (true) {
            var maybe_operator: ?Operator = if (Operator.fromTokenTag(self.token_iterator.peek(0).tag)) |explicit_operator|
                explicit_operator
            else if (!self.isAtexpressionTerminator())
                .application
            else
                null;

            if (maybe_operator) |operator| {
                const bp = infix_binding_power(operator);

                if (bp[0] < min_bp) {
                    break;
                } else {
                    const index = self.token_iterator.at();
                    // Application is implicit, there is no token to skip
                    if (operator != .application) {
                        _ = self.token_iterator.next();
                    }

                    const right_hand_side = try self.parseInfixExpression(bp[1]);
                    left_hand_side = try self.allocateAstNode(AstNode{
                        .token = index,
                        .tag = .operation,
                        .data = .{ .operation = .{
                            .lhs = left_hand_side,
                            .rhs = right_hand_side,
                        } },
                    });
                }
            } else {
                break;
            }
        }

        return left_hand_side;
    }

    fn parseAtom(self: *Self) Error!*AstNode {
        const index = self.token_iterator.at();
        const token = self.token_iterator.next();

        switch (token.tag) {
            .number => {
                return self.allocateAstNode(AstNode{ .token = index, .tag = .number, .data = undefined });
            },
            .identifier => {
                return self.allocateAstNode(AstNode{ .token = index, .tag = .identifier, .data = undefined });
            },
            .left_paren => {
                const node = try self.parseInfixExpression(0);
                if (self.token_iterator.next().tag == .right_paren) {
                    return node;
                } else {
                    return self.allocateInvalid(index, &.{.number}, &.{node});
                }
            },
            else => return self.allocateInvalid(index, &.{.number}, &.{}),
        }
    }

    fn allocateInvalid(self: *const Self, index: TokenIndex, while_parsing: []const AstNodeTag, valid_nodes: []const *AstNode) Error!*AstNode {
        var valid_nodes_list = AstNodeList.init(self.gpa);
        try valid_nodes_list.appendSlice(valid_nodes);

        return self.allocateAstNode(try AstNode.invalidFromSlice(index, valid_nodes_list, while_parsing));
    }

    fn allocateAstNode(self: *const Self, node: AstNode) !*AstNode {
        var result = try self.gpa.create(AstNode);
        result.* = node;
        return result;
    }

    fn isAtexpressionTerminator(self: *const Self) bool {
        return switch (self.token_iterator.peek(0).tag) {
            .double_arrow, .comma, .semicolon, .right_paren, .right_curly_brace, .right_square_bracket, .eof => true,
            else => false,
        };
    }

    fn expectToken(self: *Self, token_tag: Token.Tag) ?Token {
        if (self.atToken(token_tag)) {
            return self.token_iterator.next();
        } else {
            return null;
        }
    }

    fn atToken(self: *Self, token_tag: Token.Tag) bool {
        return self.token_iterator.peek(0).tag == token_tag;
    }

    fn atEof(self: *const Self) bool {
        return self.token_iterator.isDone();
    }
};
