const std = @import("std");
const imports = .{
    .sema = @import("../sema/sema.zig"),
    .irt = @import("../sema/irt.zig"),
    .llvm = @import("llvm.zig"),
};

const llvm = imports.llvm;
const SemaResult = imports.sema.Result;
const IrtNode = imports.irt.Node;
const IrtType = imports.irt.Type;
const IrtTypeIndex = imports.irt.TypeIndex;
const entry_point: [:0]const u8 = "main";
const Allocator = std.mem.Allocator;

pub fn compile(allocator: Allocator, sema: SemaResult) !CodegenResult {
    return Codegen.run(allocator, sema);
}

pub const CodegenResult = struct {
    const Self = @This();

    module: llvm.Module,

    pub fn execute(self: Self) !i32 {
        llvm.initializeInterpreter();

        const execution_engine = try self.module.createExecutionEngine();
        const entry_function = try self.module.getNamedFunction(entry_point);
        return execution_engine.runFunctionAsMain(entry_function);
    }

    pub fn deinit(self: Self) void {
        self.module.deinit();
    }
};

const Codegen = struct {
    const Self = @This();

    allocator: Allocator,
    context: llvm.Context,
    module: llvm.Module,
    builder: llvm.Builder,
    sema: SemaResult,

    int32_type: llvm.TypeRef,
    ptr_type: llvm.TypeRef,

    fn run(allocator: Allocator, sema: SemaResult) !CodegenResult {
        const context = try llvm.Context.create();
        const builder = try context.createBuilder();
        const module = try llvm.Module.createWithNameInContext("test.lemma", context);

        const self = Self{
            .allocator = allocator,
            .context = context,
            .builder = builder,
            .module = module,
            .sema = sema,
            .int32_type = try context.int32Type(),
            .ptr_type = try context.ptrType(0),
        };

        if (sema.getRoot().tag == .function) {
            _ = try self.generate(sema.getRoot(), entry_point);
        } else {
            const main_function = try module.addFunction(entry_point, &.{ self.int32_type, self.ptr_type }, self.int32_type);
            const block = try main_function.append_basic_block("entry");
            builder.positionAtEnd(block);

            const value = try self.generate(sema.getRoot(), null);
            _ = try self.builder.buildReturn(value);
        }

        return CodegenResult{ .module = self.module };
    }

    fn generate(self: *const Self, node: *const IrtNode, function_name: ?[:0]const u8) !llvm.ValueRef {
        switch (node.tag) {
            .number => return llvm.createConstInt(self.int32_type, @intCast(node.data.number), false),
            .builtin => {
                const lhs = try self.generate(self.sema.getNode(node.data.builtin.arguments.items[0]), null);
                const rhs = try self.generate(self.sema.getNode(node.data.builtin.arguments.items[1]), null);

                switch (node.data.builtin.operation) {
                    .addition => return self.builder.buildAdd(lhs, rhs, ""),
                    .subtraction => return self.builder.buildSub(lhs, rhs, ""),
                    .multiplication => return self.builder.buildMul(lhs, rhs, ""),
                    .division => return self.builder.buildSDiv(lhs, rhs, ""),
                }
            },
            .function => {
                var arguments = std.ArrayList(llvm.TypeRef).init(self.allocator);
                defer arguments.deinit();

                for (node.data.function.arguments.items) |argument_index| {
                    const irt_type_index = self.sema.getNodeTypeIndex(argument_index);
                    try arguments.append(try self.irtToLLVMType(irt_type_index));
                }

                const return_type_index = self.sema.getNodeTypeIndex(node.data.function.body);
                const function = try self.module.addFunction(
                    function_name orelse unreachable,
                    arguments.items,
                    try self.irtToLLVMType(return_type_index),
                );
                const block = try function.append_basic_block("entry");
                self.builder.positionAtEnd(block);

                const value = try self.generate(self.sema.getNode(node.data.function.body), null);

                _ = try self.builder.buildReturn(value);

                return function.ref;
            },
            else => unreachable,
        }
    }

    fn irtToLLVMType(self: Self, irt_type_index: IrtTypeIndex) !llvm.TypeRef {
        const irt_type = self.sema.getType(irt_type_index);

        switch (irt_type.*) {
            .number => return self.int32_type,
            .arrow => |arrow| {
                var arguments = std.ArrayList(llvm.TypeRef).init(self.allocator);
                defer arguments.deinit();

                try arguments.insert(0, try self.irtToLLVMType(arrow.argument));

                var return_irt_type_index = arrow.result;
                var return_irt_type = self.sema.getType(return_irt_type_index);

                while (return_irt_type.* == .arrow) {
                    try arguments.insert(0, try self.irtToLLVMType(return_irt_type.arrow.argument));
                    return_irt_type_index = return_irt_type.arrow.result;
                    return_irt_type = self.sema.getType(return_irt_type_index);
                }

                return llvm.functionType(arguments.items, try self.irtToLLVMType(return_irt_type_index));
            },
            else => unreachable,
        }
    }
};
