const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
};

const Value = imports.common.Value;
const String = std.ArrayList(u8);

pub const NodeList = std.ArrayList(*Node);
pub const Token = imports.lexer.Token;
pub const TokenIndex = imports.lexer.TokenIndex;
pub const SourceSpan = imports.common.meta.SourceSpan;

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
            lhs: *Node,
            rhs: *Node,
        },
        function: struct {
            arguments: NodeList,
            body: *Node,
        },
        //TODO: add expected_instead
        invalid: struct {
            while_parsing: TagBoundedArray,
            valid_nodes: NodeList,
        },
    },

    pub const Tag = enum {
        number,
        operation,
        pattern,
        function,
        identifier,

        invalid,
    };

    const TagBoundedArray = std.BoundedArray(Tag, 4);

    const Self = @This();

    pub fn invalidFromSlice(token: TokenIndex, valid_nodes: NodeList, while_parsing: []const Tag) !Self {
        var while_parsing_array = try TagBoundedArray.fromSlice(while_parsing);
        return Self{ .token = token, .tag = .invalid, .data = .{ .invalid = .{ .while_parsing = while_parsing_array, .valid_nodes = valid_nodes } } };
    }
};
