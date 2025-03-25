const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
};

pub const NodeIndexList = std.ArrayList(NodeIndex);
pub const Token = imports.lexer.Token;
pub const TokenIndex = imports.lexer.TokenIndex;
pub const NodeIndex = u32;

pub const Operator = enum {
    addition,
    subtraction,
    multiplication,
    division,
    forwarding,
    application,

    const Self = @This();

    pub fn fromTokenTag(token_tag: Token.Tag) ?Self {
        return switch (token_tag) {
            .plus => .addition,
            .minus => .subtraction,
            .star => .multiplication,
            .slash => .division,
            .pipe => .forwarding,
            else => null,
        };
    }
};

pub const Node = struct {
    token: TokenIndex,
    tag: Tag,
    data: union {
        operation: struct {
            operator: Operator,
            lhs: NodeIndex,
            rhs: NodeIndex,
        },
        function: struct {
            arguments: NodeIndexList,
            body: NodeIndex,
        },
        assignment: struct {
            binding: NodeIndex,
            value: NodeIndex,
        },
        //TODO: add expected_instead
        invalid: struct {
            while_parsing: TagBoundedArray,
            valid_nodes: NodeIndexList,
        },
    },

    pub const Tag = enum {
        number,
        identifier,
        binding,
        function,
        letin,
        assignment,
        operation, // binary operation

        invalid,
    };

    const TagBoundedArray = std.BoundedArray(Tag, 4);

    const Self = @This();

    pub fn invalidFromSlice(token: TokenIndex, valid_nodes: NodeIndexList, while_parsing: []const Tag) !Self {
        var while_parsing_array = try TagBoundedArray.fromSlice(while_parsing);
        return Self{ .token = token, .tag = .invalid, .data = .{ .invalid = .{ .while_parsing = while_parsing_array, .valid_nodes = valid_nodes } } };
    }
};
