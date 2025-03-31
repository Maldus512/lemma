const std = @import("std");

const imports = .{
    .irt = @import("irt.zig"),
};

const Allocator = std.mem.Allocator;
const Type = imports.irt.Type;
const TypeVariable = imports.irt.TypeVariable;
const Index = u32;
const TypeList = std.ArrayList(Type);
const TypeIndex = imports.irt.TypeIndex;
pub const NodeList = std.ArrayList(Node);

pub const MergeFindSet = struct {
    nodes: NodeList,
    type_list: TypeList,
    number_type_index: TypeIndex,
    invalid_type_index: TypeIndex,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var type_list = TypeList.init(allocator);

        const number_type_index: TypeIndex = @intCast(type_list.items.len);
        try type_list.append(.number);
        const invalid_type_index: TypeIndex = @intCast(type_list.items.len);
        try type_list.append(.invalid);

        return Self{
            .nodes = NodeList.init(allocator),
            .type_list = type_list,
            .number_type_index = number_type_index,
            .invalid_type_index = invalid_type_index,
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.type_list.deinit();
    }

    pub fn makeNew(self: *Self) !TypeIndex {
        const type_variable: TypeVariable = @intCast(self.nodes.items.len);
        const type_index = try self.allocateType(Type{ .variable = type_variable });

        try self.nodes.append(Node{
            .root = .{
                .value = type_index,
                .rank = 0,
            },
        });
        return type_index;
    }

    pub fn mergeVariableVariable(self: *Self, type_variable_1: TypeVariable, type_variable_2: TypeVariable) void {
        const representative_index_1 = self.find(type_variable_1);
        const representative_index_2 = self.find(type_variable_2);

        // If they have the same representative nothing needs to be done
        if (representative_index_1 != representative_index_2) {
            const unified_value = self.unifyTypes(representative_index_1, representative_index_2);

            const representative_1 = &self.nodes.items[representative_index_1];
            const representative_2 = &self.nodes.items[representative_index_2];

            if (representative_1.root.rank == representative_2.root.rank) {
                // Arbitrary choice
                representative_1.root.rank += 1;
                representative_2.* = Node{ .node = representative_index_1 };
                representative_1.root.value = unified_value;
            } else if (representative_1.root.rank > representative_2.root.rank) {
                representative_2.* = Node{ .node = representative_index_1 };
                representative_1.root.value = unified_value;
            } else {
                representative_1.* = Node{ .node = representative_index_2 };
                representative_2.root.value = unified_value;
            }
        }
    }

    pub fn mergeVariableType(self: *Self, type_variable: TypeVariable, type_index: TypeIndex) void {
        const representative_index = self.find(type_variable);
        const variable_type_index = self.nodes.items[representative_index].root.value;

        const unified_value = self.unifyTypes(variable_type_index, type_index);
        const representative = &self.nodes.items[representative_index];
        representative.root.value = unified_value;
    }

    pub fn find(self: *const Self, type_variable: TypeVariable) Index {
        //TODO: flatten tree while traversing
        var representative_index = type_variable;

        while (self.nodes.items[representative_index] == .node) {
            representative_index = self.nodes.items[representative_index].node;
        }
        return representative_index;
    }

    pub fn findType(self: *const Self, type_variable: TypeVariable) ?TypeIndex {
        return switch (self.nodes.items[type_variable]) {
            .root => |root| {
                const found_type = self.getType(root.value);
                if (found_type.* != .variable or found_type.variable != type_variable) {
                    return root.value;
                } else {
                    return null;
                }
            },
            else => null,
        };
    }

    fn unifyTypes(self: *const Self, type_index_1: TypeIndex, type_index_2: TypeIndex) TypeIndex {
        const type_1 = self.getType(type_index_1);
        const type_2 = self.getType(type_index_2);

        if (type_1.* == .variable and type_2.* == .variable) {
            return type_index_1;
        } else if (type_1.* == .variable) {
            return type_index_2;
        } else if (type_2.* == .variable) {
            return type_index_1;
        } else if (self.typesAreEqual(type_index_1, type_index_2)) {
            return type_index_1;
        } else {
            return self.invalid_type_index;
        }
    }

    pub fn normalizeType(self: *Self, type_index: TypeIndex) void {
        const type_to_normalize = self.getType(type_index);

        switch (type_to_normalize.*) {
            .number => {},
            .arrow => |arrow| {
                self.normalizeType(arrow.argument);
                self.normalizeType(arrow.result);
            },
            .variable => |variable| {
                if (self.findType(variable)) |new_type_index| {
                    //std.log.warn("Assigning var {s} to {s}", .{
                    //    Type.show(std.heap.page_allocator, &self.type_list, type_index) catch unreachable,
                    //    Type.show(std.heap.page_allocator, &self.type_list, new_type_index) catch unreachable,
                    //});
                    self.normalizeType(new_type_index);
                    self.type_list.items[type_index] = self.getType(new_type_index).*;
                }
            },
            .invalid => {},
        }
    }

    pub fn allocateType(self: *Self, ltype: Type) !TypeIndex {
        if (ltype == .invalid) {
            return self.invalid_type_index;
        } else if (ltype == .number) {
            return self.number_type_index;
        } else {
            const index = self.type_list.items.len;
            try self.type_list.append(ltype);
            return @intCast(index);
        }
    }

    fn typesAreEqual(self: *const Self, type_index_1: TypeIndex, type_index_2: TypeIndex) bool {
        const type_1 = self.getType(type_index_1);
        const type_2 = self.getType(type_index_2);

        if (type_1.* == .number and type_2.* == .number) {
            return true;
        } else if (type_1.* == .variable and type_2.* == .variable) {
            return type_1.variable == type_2.variable;
        } else if (type_1.* == .invalid and type_2.* == .invalid) {
            return true;
        } else if (type_1.* == .arrow and type_2.* == .arrow) {
            return self.typesAreEqual(type_1.arrow.argument, type_2.arrow.argument) and self.typesAreEqual(type_1.arrow.result, type_2.arrow.result);
        } else {
            return false;
        }
    }

    fn getType(self: *const Self, index: TypeIndex) *Type {
        return &self.type_list.items[index];
    }
};

const Node = union(enum) {
    node: Index,
    root: struct {
        value: TypeIndex,
        rank: u16,
    },
};
