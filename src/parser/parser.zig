const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
    .ast = @import("ast.zig"),
};

pub const AstNodeTag = imports.ast.AstNodeTag;

const String = std.ArrayList(u8);
const Allocator = std.mem.Allocator;
const SourceSpan = imports.common.meta.SourceSpan;
const ScanResult = imports.lexer.ScanResult;
const ScanResultIterator = imports.lexer.ScanResultIterator;
const AstNodeList = imports.ast.AstNodeList;
const AstNode = imports.ast.AstNode;
const AstNodeTagBoundedArray = imports.ast.AstNodeTagBoundedArray;
const Operator = imports.ast.Operator;
const Token = imports.lexer.Token;
const TokenTag = imports.lexer.TokenTag;
const Value = imports.common.Value;

const Error = error{ OutOfMemory, Overflow };

pub const ParseResult = struct {
    scan_result: ScanResult,
    ast: *AstNode,

    const Self = @This();
};

pub fn parse(allocator: Allocator, source: []const u8) !ParseResult {
    const scan_result = try imports.lexer.scan(allocator, source);

    var parser = Parser{ .allocator = allocator, .token_iterator = scan_result.intoIter() };

    return ParseResult{
        .scan_result = scan_result,
        .ast = try parser.parse(),
    };
}

const Parser = struct {
    //TODO: save errors in a list for ease of access
    allocator: Allocator,
    token_iterator: ScanResultIterator,

    const Self = @This();

    fn parse(self: *Self) !*AstNode {
        return self.parseInfixExpression(0);
    }

    const BindingPower = std.meta.Tuple(&.{ u16, u16 });

    fn infix_binding_power(op: Operator) BindingPower {
        return switch (op) {
            .forwarding => .{ 1, 2 },
            .sum, .subtraction => .{ 3, 4 },
            .multiplication, .division => .{ 5, 6 },
            .application => .{ 7, 8 },
        };
    }

    fn parseInfixExpression(self: *Self, min_bp: u16) Error!*AstNode {
        // Pratt parser

        var left_hand_side = try self.parseAtom();

        while (true) {
            if (Operator.fromToken(self.token_iterator.peek(0))) |operator| {
                const bp = infix_binding_power(operator);

                if (bp[0] < min_bp) {
                    break;
                } else {
                    _ = self.token_iterator.next();
                    const right_hand_side = try self.parseInfixExpression(bp[1]);
                    left_hand_side = try self.allocateAstNode(AstNode{
                        .operation = .{
                            .lhs = left_hand_side,
                            .operator = operator,
                            .rhs = right_hand_side,
                        },
                    });
                }
            } else {
                break;
            }
        }

        return left_hand_side;
    }

    fn parseAtom(self: *Self) Error!*AstNode {
        switch (self.token_iterator.next()) {
            Token.number => |string| {
                return self.allocateAstNode(AstNode{ .number = parseNumber(string) });
            },
            Token.left_paren => {
                const node = try self.parseInfixExpression(0);
                if (self.token_iterator.next().is(.right_paren)) {
                    return node;
                } else {
                    return self.allocateInvalid(&.{.number}, &.{node});
                }
            },
            else => return self.allocateInvalid(&.{.number}, &.{}),
        }
    }

    fn allocateInvalid(self: *const Self, while_parsing: []const AstNodeTag, valid_nodes: []const *AstNode) Error!*AstNode {
        var while_parsing_array = try AstNodeTagBoundedArray.fromSlice(while_parsing);
        var valid_nodes_list = AstNodeList.init(self.allocator);
        try valid_nodes_list.appendSlice(valid_nodes);

        return self.allocateAstNode(AstNode{
            .invalid = .{
                .while_parsing = while_parsing_array,
                .valid_nodes = valid_nodes_list,
            },
        });
    }

    fn allocateAstNode(self: *const Self, node: AstNode) !*AstNode {
        var result = try self.allocator.create(AstNode);
        result.* = node;
        return result;
    }

    fn expectToken(self: *Self, token_tag: TokenTag) ?Token {
        if (self.atToken(token_tag)) {
            return self.token_iterator.next();
        } else {
            return null;
        }
    }

    fn atToken(self: *Self, token_tag: TokenTag) bool {
        return self.token_iterator.peek(0).is(token_tag);
    }

    fn atEof(self: *const Self) bool {
        return self.token_iterator.isDone();
    }
};

fn parseNumber(string: String) i64 {
    return std.fmt.parseInt(i64, string.items, 0) catch unreachable;
}
