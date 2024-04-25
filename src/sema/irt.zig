const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .parser = @import("../parser/parser.zig"),
    .common = @import("../common/common.zig"),
};

const Allocator = std.mem.Allocator;
pub const NodeIndexList = std.ArrayList(NodeIndex);
pub const TypeList = std.ArrayList(Type);
pub const TokenIndex = imports.lexer.TokenIndex;
pub const TypeVariable = u32;
pub const NodeIndex = u32;
pub const TypeIndex = u32;

pub const BuiltinOperation = enum {
    addition,
    subtraction,
    multiplication,
    division,
};

pub const Node = struct {
    tag: Tag,
    data: union {
        number: isize,
        binding: struct {
            token: TokenIndex,
        },
        bound_identifier: NodeIndex,
        builtin: BuiltinOperation,
        function: struct {
            arguments: NodeIndexList,
            body: NodeIndex,
        },
        application: struct {
            function: NodeIndex,
            arguments: NodeIndexList,
        },
        free_identifier: TokenIndex,
    },
    inferred_type: TypeIndex,

    pub const Tag = enum {
        number,
        binding,
        boundIdentifier,
        builtin,
        application,
        function,

        freeIdentifier,
        invalid,
    };

    const Self = @This();
};

pub const Type = union(enum) {
    number,
    variable: TypeVariable,
    arrow: struct {
        argument: TypeIndex,
        result: TypeIndex,
    },
    invalid,

    pub fn show(allocator: Allocator, type_list: *const TypeList, index: TypeIndex) ![]const u8 {
        return Type.showNormalized(allocator, type_list, index, null);
    }

    fn showNormalized(allocator: Allocator, type_list: *const TypeList, index: TypeIndex, variable_base: ?TypeVariable) ![]const u8 {
        const fmt = std.fmt;

        switch (type_list.items[index]) {
            .number => return fmt.allocPrint(allocator, "Num", .{}),
            .variable => |variable| {
                var normalized_variable = variable;

                if (variable_base) |unwrapped_variable_base| {
                    if (unwrapped_variable_base < normalized_variable) {
                        normalized_variable -= unwrapped_variable_base;
                    }
                }

                var result = try fmt.allocPrint(allocator, "", .{});
                var character = normalized_variable;
                const max = 'z' - 'a';

                while (character > max) {
                    result = try fmt.allocPrint(allocator, "{s}{c}", .{ result, 'a' + @intCast(u8, character % max) });
                    character -= max;
                }

                return fmt.allocPrint(allocator, "{s}{c}", .{ result, 'a' + @intCast(u8, character) });
            },
            .arrow => |arrow| {
                const argument = type_list.items[arrow.argument];
                const next_variable_base = if (argument == .variable and variable_base != null) argument.variable else variable_base;

                const argument_show = try Type.showNormalized(allocator, type_list, arrow.argument, next_variable_base);
                const result_show = try Type.showNormalized(allocator, type_list, arrow.result, next_variable_base);
                if (argument == .arrow) {
                    return fmt.allocPrint(allocator, "({s})->{s}", .{ argument_show, result_show });
                } else {
                    return fmt.allocPrint(allocator, "{s}->{s}", .{ argument_show, result_show });
                }
            },
            .invalid => return fmt.allocPrint(allocator, "BOTTOM", .{}),
        }
    }
};
