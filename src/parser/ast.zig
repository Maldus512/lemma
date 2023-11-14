const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
};

const Value = imports.common.Value;
const String = std.ArrayList(u8);

pub const AstNodeList = std.ArrayList(*AstNode);
pub const Token = imports.lexer.Token;
pub const TokenIndex = imports.lexer.TokenIndex;
pub const SourceSpan = imports.common.meta.SourceSpan;
pub const AstNodeTagBoundedArray = std.BoundedArray(AstNodeTag, 4);

pub const Operator = enum {
    sum,
    subtraction,
    multiplication,
    division,
    forwarding,
    application,

    const Self = @This();

    pub fn fromToken(token: Token) ?Self {
        return switch (token) {
            .plus => .sum,
            .minus => .subtraction,
            .star => .multiplication,
            .slash => .division,
            .pipe => .forwarding,
            else => null,
        };
    }
};

pub const AstNodeTag = enum {
    number,
    operation,

    invalid,
};

pub const AstNode = union(AstNodeTag) {
    number: i64,
    operation: struct {
        lhs: *AstNode,
        operator: Operator,
        rhs: *AstNode,
    },
    //TODO: add expected_instead
    invalid: struct {
        while_parsing: AstNodeTagBoundedArray,
        valid_nodes: AstNodeList,
    },

    const Self = @This();

    pub fn is(self: *const Self, tag: AstNodeTag) bool {
        return @as(AstNodeTag, self.*) == tag;
    }
};
