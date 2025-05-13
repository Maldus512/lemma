const std = @import("std");

const imports = .{
    .lexer = @import("../lexer/lexer.zig"),
    .common = @import("../common/common.zig"),
    .parser = @import("../parser/parser.zig"),
    .ast = @import("../parser/ast.zig"),
    .irt = @import("irt.zig"),
    .mfset = @import("mfset.zig"),
};

const Allocator = std.mem.Allocator;
const AstNode = imports.ast.Node;
const AstNodeIndex = imports.ast.NodeIndex;
const BuiltinOperation = imports.irt.BuiltinOperation;
const IrtNodeIndex = imports.irt.NodeIndex;
const IrtNodeIndexList = imports.irt.NodeIndexList;
const IrtNode = imports.irt.Node;
const MergeFindSet = imports.mfset.MergeFindSet;

const IrtNodeList = std.ArrayList(IrtNode);
const Type = imports.irt.Type;
const TypeIndex = imports.irt.TypeIndex;
const TypeVariable = imports.irt.TypeVariable;
const TypeList = std.ArrayList(Type);
const Token = imports.lexer.Token;
const TokenIndex = imports.lexer.TokenIndex;
const ParseResult = imports.parser.ParseResult;
const Environment = std.StringHashMap(IrtNodeIndex);
const Constraints = std.ArrayList(std.meta.Tuple(&.{ TypeIndex, TypeIndex }));

pub const Result = struct {
    root: IrtNodeIndex,
    node_list: IrtNodeList,
    type_list: TypeList,
    constraints: Constraints,

    const Self = @This();

    pub fn getNode(self: *const Self, index: IrtNodeIndex) *const IrtNode {
        return &self.node_list.items[index];
    }

    pub fn getNodeTypeIndex(self: *const Self, index: IrtNodeIndex) TypeIndex {
        return self.node_list.items[index].inferred_type;
    }

    pub fn getType(self: *const Self, index: TypeIndex) *const Type {
        return &self.type_list.items[index];
    }

    pub fn getRoot(self: *const Self) *const IrtNode {
        return self.getNode(self.root);
    }

    pub fn displayType(self: *const Self, allocator: Allocator, index: TypeIndex) ![]const u8 {
        return Type.show(allocator, &self.type_list, index);
    }

    /// Deinitialize
    pub fn deinit(self: *const Self) void {
        self.constraints.deinit();
        for (self.node_list.items) |node| {
            node.deinit();
        }
        self.node_list.deinit();
        self.type_list.deinit();
    }
};

pub fn analyze(gpa: Allocator, source: []const u8) !Result {
    const parse_result = try imports.parser.parse(gpa, source);

    var sema = try Sema.new(gpa, parse_result);

    const root = try sema.analyze();
    parse_result.deinit();

    sema.mfset.nodes.deinit();
    sema.env.deinit();

    return Result{
        .root = root,
        .node_list = sema.node_list,
        .type_list = sema.mfset.type_list,
        .constraints = sema.constraints,
    };
}

const Sema = struct {
    //TODO: save errors in a list for ease of access
    gpa: Allocator,
    mfset: MergeFindSet,
    ast: ParseResult,
    node_list: IrtNodeList,
    env: Environment,
    constraints: Constraints,

    const Self = @This();

    fn new(gpa: Allocator, parse_result: ParseResult) !Self {
        const mfset = try MergeFindSet.init(gpa);
        const node_list = IrtNodeList.init(gpa);

        return Sema{
            .gpa = gpa,
            .mfset = mfset,
            .ast = parse_result,
            .node_list = node_list,
            .env = Environment.init(gpa),
            .constraints = Constraints.init(gpa),
        };
    }

    fn analyze(self: *Self) !IrtNodeIndex {
        const node_index = try self.ast_to_it(self.ast.root);

        self.unify();
        //std.log.warn("Normalizing {s}", .{ Type.show(std.heap.page_allocator, &self.mfset.type_list, self.getNode(node_index).inferred_type) catch unreachable, });
        self.mfset.normalizeType(self.getNode(node_index).inferred_type);

        return node_index;
    }

    fn unify(self: *Self) void {
        for (self.constraints.items) |constraint| {
            //std.log.warn("constraint {s} == {s}", .{
            //    Type.show(std.heap.page_allocator, &self.mfset.type_list, constraint[0]) catch unreachable,
            //    Type.show(std.heap.page_allocator, &self.mfset.type_list, constraint[1]) catch unreachable,
            //});
            self.unifyTypeType(constraint[0], constraint[1]);
        }
    }

    fn unifyTypeType(self: *Self, type_index_1: TypeIndex, type_index_2: TypeIndex) void {
        self.mfset.normalizeType(type_index_1);
        self.mfset.normalizeType(type_index_2);

        const type_1 = self.getType(type_index_1);
        const type_2 = self.getType(type_index_2);

        if (type_1.* == .number and type_2.* == .number) {
            // All nice and dandy
        }
        // Two functions
        else if (type_1.* == .arrow and type_2.* == .arrow) {
            self.unifyTypeType(type_1.arrow.argument, type_2.arrow.argument);
            self.unifyTypeType(type_1.arrow.result, type_2.arrow.result);
        }
        // Two variables
        else if (type_1.* == .variable and type_2.* == .variable) {
            self.mfset.mergeVariableVariable(type_1.variable, type_2.variable);
        }
        // Only 1 is a variable
        else if (type_1.* == .variable) {
            if (self.occurs(type_index_2, type_1.variable)) {
                self.mfset.mergeVariableType(type_1.variable, self.mfset.invalid_type_index);
            } else {
                self.mfset.mergeVariableType(type_1.variable, type_index_2);
            }
        }
        // Only 2 is a variable
        else if (type_2.* == .variable) {
            if (self.occurs(type_index_1, type_2.variable)) {
                self.mfset.mergeVariableType(type_2.variable, self.mfset.invalid_type_index);
            } else {
                self.mfset.mergeVariableType(type_2.variable, type_index_1);
            }
        } else {
            // TODO: types can't be equal, signal error
            //unreachable;
        }
    }

    fn ast_to_it(self: *Self, ast_node_index: AstNodeIndex) !IrtNodeIndex {
        const ast_node = self.ast.getNode(ast_node_index);

        switch (ast_node.tag) {
            .number => return self.allocateNumber(self.ast.getNumberValue(ast_node_index)),
            .identifier => {
                const string = self.ast.getSourceSlice(ast_node_index);
                if (self.env.get(string)) |origin| {
                    return self.allocateBoundIdentifier(origin);
                } else {
                    return self.allocateFreeIdentifier();
                }
            },
            .binding => unreachable,
            .function => {
                var shadow_map = Environment.init(self.gpa);
                defer shadow_map.deinit();
                var new_map = Environment.init(self.gpa);
                defer new_map.deinit();

                var it_arguments = IrtNodeIndexList.init(self.gpa);

                for (ast_node.data.function.arguments.items) |argument| {
                    try it_arguments.append(try self.addItemToEnvironment(&shadow_map, &new_map, argument));
                }

                const body = try self.ast_to_it(ast_node.data.function.body);

                var new_iterator = new_map.keyIterator();
                while (new_iterator.next()) |key| {
                    _ = self.env.remove(key.*);
                }

                var shadow_iterator = shadow_map.iterator();
                while (shadow_iterator.next()) |entry| {
                    try self.env.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                return self.allocateFunction(it_arguments, body);
            },
            .operation => {
                switch (ast_node.data.operation.operator) {
                    .application => {
                        var arguments = IrtNodeIndexList.init(self.gpa);

                        var next = ast_node_index;
                        while (self.ast.getNode(next).tag == .operation and self.ast.getNode(next).data.operation.operator == .application) {
                            try arguments.append(try self.ast_to_it(self.ast.getNode(next).data.operation.rhs));
                            next = self.ast.getNode(next).data.operation.lhs;
                        }
                        // First of the application chain
                        const function = try self.ast_to_it(next);

                        return self.allocateApplication(function, arguments);
                    },
                    .forwarding => {
                        var arguments = IrtNodeIndexList.init(self.gpa);
                        try arguments.append(try self.ast_to_it(ast_node.data.operation.lhs));

                        const function = try self.ast_to_it(ast_node.data.operation.rhs);

                        return self.allocateApplication(function, arguments);
                    },
                    .addition, .subtraction, .multiplication, .division => {
                        return self.allocateBuiltin(
                            BuiltinOperation.fromAstOperator(ast_node.data.operation.operator) orelse unreachable,
                            try self.ast_to_it(ast_node.data.operation.lhs),
                            try self.ast_to_it(ast_node.data.operation.rhs),
                        );
                    },
                }
            },
            .letin => unreachable,
            .assignment => unreachable,
            .invalid => return self.allocateInvalid(),
        }
    }

    /// Create a symbol binding and add it to the new environment (shadowing eventual omonyms)
    fn addItemToEnvironment(self: *Self, shadow_map: *Environment, new_map: *Environment, item: AstNodeIndex) !IrtNodeIndex {
        const ast_node = self.ast.getNode(item);

        if (ast_node.tag == AstNode.Tag.binding) {
            const id = self.ast.getSourceSlice(item);
            if (self.env.get(id)) |previous| {
                try shadow_map.put(id, previous);
            }
            const result = try self.allocateBinding(ast_node.token);
            try new_map.put(id, result);
            try self.env.put(id, result);
            return result;
        } else {
            return self.allocateInvalid();
        }
    }

    fn allocateNode(self: *Self, node: IrtNode) !IrtNodeIndex {
        const index = self.node_list.items.len;
        try self.node_list.append(node);
        return @intCast(index);
    }

    fn allocateNumber(self: *Self, value: isize) !IrtNodeIndex {
        return self.allocateNode(IrtNode{
            .tag = .number,
            .data = .{ .number = value },
            .inferred_type = try self.mfset.allocateType(.number), // TODO: constant types don't need to be allocated every time
        });
    }

    fn allocateBinding(self: *Self, token: TokenIndex) !IrtNodeIndex {
        return self.allocateNode(IrtNode{
            .tag = .binding,
            .data = .{ .binding = .{ .token = token } },
            .inferred_type = try self.mfset.makeNew(),
        });
    }

    fn allocateBoundIdentifier(self: *Self, bind: IrtNodeIndex) !IrtNodeIndex {
        const node = self.node_list.items[bind];
        return self.allocateNode(IrtNode{
            .tag = .boundIdentifier,
            .data = .{ .bound_identifier = bind },
            .inferred_type = node.inferred_type,
        });
    }

    fn allocateFreeIdentifier(self: *Self) !IrtNodeIndex {
        return self.allocateNode(IrtNode{
            .tag = .freeIdentifier,
            .data = undefined,
            .inferred_type = try self.mfset.allocateType(.invalid),
        });
    }

    fn allocateFunction(self: *Self, arguments: IrtNodeIndexList, body: IrtNodeIndex) !IrtNodeIndex {
        var first: ?TypeIndex = null;
        var cursor: TypeIndex = undefined;

        for (arguments.items) |argument| {
            const next = try self.mfset.allocateType(Type{
                .arrow = .{
                    .argument = self.getNode(argument).inferred_type,
                    .result = undefined,
                },
            });

            if (first == null) {
                first = next;
                cursor = next;
            }

            self.getType(cursor).arrow.result = next;
            cursor = next;
        }

        self.getType(cursor).arrow.result = self.getNode(body).inferred_type;

        return self.allocateNode(IrtNode{
            .tag = .function,
            .data = .{ .function = .{
                .arguments = arguments,
                .body = body,
            } },
            .inferred_type = first orelse unreachable,
        });
    }

    fn allocateApplication(self: *Self, fun: IrtNodeIndex, arguments: IrtNodeIndexList) !IrtNodeIndex {
        const function_node = self.getNode(fun);
        var function_type = function_node.inferred_type;
        var result_type: TypeIndex = undefined;
        var index: usize = arguments.items.len;

        // The argument list for an application is reversed
        while (index > 0) {
            index -= 1;

            const argument = arguments.items[index];
            result_type = try self.mfset.makeNew();
            const arrow_type = try self.mfset.allocateType(Type{
                .arrow = .{
                    .argument = self.getNode(argument).inferred_type,
                    .result = result_type,
                },
            });

            try self.addEqualityTypeConstraint(function_type, arrow_type);
            function_type = result_type;
        }

        const final_type = result_type;

        return self.allocateNode(IrtNode{
            .tag = .application,
            .data = .{ .application = .{
                .function = fun,
                .arguments = arguments,
            } },
            .inferred_type = final_type,
        });
    }

    fn allocateBuiltin(self: *Self, operation: BuiltinOperation, lhs: IrtNodeIndex, rhs: IrtNodeIndex) !IrtNodeIndex {
        var arguments = IrtNodeIndexList.init(self.gpa);
        try arguments.append(lhs);
        try arguments.append(rhs);

        return self.allocateNode(IrtNode{
            .tag = .builtin,
            .data = .{ .builtin = .{
                .operation = operation,
                .arguments = arguments,
            } },
            .inferred_type = self.mfset.number_type_index,
        });
    }

    fn allocateInvalid(self: *Self) !IrtNodeIndex {
        return self.allocateNode(IrtNode{
            .tag = .invalid,
            .data = undefined,
            .inferred_type = try self.mfset.allocateType(.invalid),
        });
    }

    fn getNode(self: *const Self, index: IrtNodeIndex) *IrtNode {
        return &self.node_list.items[index];
    }

    fn getType(self: *const Self, index: TypeIndex) *Type {
        return &self.mfset.type_list.items[index];
    }

    fn addEqualityTypeConstraint(self: *Self, first: TypeIndex, second: TypeIndex) !void {
        try self.constraints.append(.{ first, second });
    }

    fn occurs(self: *const Self, type_index: TypeIndex, variable: TypeVariable) bool {
        const ltype = self.getType(type_index);
        return switch (ltype.*) {
            .number => false,
            .variable => |found| found == variable,
            .arrow => |arrow| self.occurs(arrow.argument, variable) or self.occurs(arrow.result, variable),
            .invalid => false,
        };
    }
};

//MFSet: ogni sottoinsieme e' rappresentato da un tipo.
//Tutti gli elementi in un sottoinsieme vanno sostituiti con quel tipo, che e' il loro rappresentante
