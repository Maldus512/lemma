const std = @import("std");
const Allocator = std.mem.Allocator;

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
};

pub const NodeIndexList = std.ArrayList(NodeIndex);
pub const Token = imports.lexer.Token;
pub const TokenIndex = imports.lexer.TokenIndex;
pub const NodeIndex = u32;

/// Builtin operators
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

/// AST Node
/// The tree is organized with indexes over an external node array instead of pointers
/// in order to save RAM and improve cache locality
pub const Node = struct {
    /// Index for the corresponding initial token
    token: TokenIndex,
    tag: Tag,
    /// Union that contains data
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
            while_parsing: [4]Tag,
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

    const Self = @This();

    /// Invalid node constructor
    pub fn invalidFromSlice(token: TokenIndex, valid_nodes: NodeIndexList, while_parsing: []const Tag) !Self {
        var self = Self{
            .token = token,
            .tag = .invalid,
            .data = .{
                .invalid = .{ .while_parsing = undefined, .valid_nodes = valid_nodes },
            },
        };
        @memcpy(&self.data.invalid.while_parsing, while_parsing[0..while_parsing.len]);

        return self;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.tag) {
            .function => {
                self.data.function.arguments.deinit(allocator);
            },
            .invalid => {
                self.data.invalid.valid_nodes.deinit(allocator);
            },
            else => {},
        }
    }
};
