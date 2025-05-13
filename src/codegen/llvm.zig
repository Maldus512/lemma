const c_llvm = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/ExecutionEngine.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/Analysis.h");
    @cInclude("llvm-c/BitWriter.h");
});

pub const TypeRef = *c_llvm.struct_LLVMOpaqueType;
pub const ValueRef = *c_llvm.struct_LLVMOpaqueValue;
pub const GenericValueRef = *c_llvm.struct_LLVMOpaqueGenericValue;
pub const BasicBlockRef = *c_llvm.struct_LLVMOpaqueBasicBlock;
pub const BuilderRef = *c_llvm.struct_LLVMOpaqueBuilder;
pub const ExecutionEngineRef = *c_llvm.struct_LLVMOpaqueExecutionEngine;

var initialized = false;

pub fn createConstInt(const_type: TypeRef, value: u64, sign_extend: bool) !ValueRef {
    return c_llvm.LLVMConstInt(const_type, value, if (sign_extend) 1 else 0) orelse error.LLVMError;
}

pub fn genericValueTo(ToType: type, value: GenericValueRef) !ToType {
    const type_info = @typeInfo(type);
    switch (type_info) {
        .int => return c_llvm.LLVMGenericValueToInt(value, 0) orelse error.LLVMError,
        else => unreachable,
    }
}

pub fn initializeInterpreter() void {
    if (!initialized) {
        c_llvm.LLVMLinkInInterpreter();
        _ = c_llvm.LLVMInitializeNativeTarget();
        _ = c_llvm.LLVMInitializeNativeAsmPrinter();
        _ = c_llvm.LLVMInitializeNativeAsmParser();
        initialized = true;
    }
}

pub fn functionType(param_types: []const TypeRef, return_type: TypeRef) !TypeRef {
    return c_llvm.LLVMFunctionType(
        return_type,
        @ptrCast(@constCast(param_types.ptr)),
        @intCast(param_types.len),
        0,
    ) orelse return error.LLVMError;
}

pub const Context = struct {
    const Self = @This();

    ref: *c_llvm.struct_LLVMOpaqueContext,

    pub fn create() !Self {
        return Self{ .ref = c_llvm.LLVMContextCreate() orelse return error.LLVMError };
    }

    pub fn int32Type(self: Self) !TypeRef {
        return c_llvm.LLVMInt32TypeInContext(self.ref) orelse error.LLVMError;
    }

    pub fn ptrType(self: Self, address_space: u32) !TypeRef {
        return c_llvm.LLVMPointerTypeInContext(self.ref, address_space) orelse error.LLVMError;
    }

    pub fn createBuilder(self: Self) !Builder {
        return Builder{ .ref = c_llvm.LLVMCreateBuilderInContext(self.ref) orelse return error.LLVMError };
    }
};

pub const Module = struct {
    const Self = @This();

    ref: *c_llvm.struct_LLVMOpaqueModule,

    pub fn addFunction(self: Self, name: [:0]const u8, param_types: []const TypeRef, return_type: TypeRef) !Function {
        return Function{
            .ref = c_llvm.LLVMAddFunction(self.ref, name.ptr, c_llvm.LLVMFunctionType(
                return_type,
                @ptrCast(@constCast(param_types.ptr)),
                @intCast(param_types.len),
                0,
            )) orelse return error.LLVMError,
        };
    }

    pub fn createWithNameInContext(module_id: [:0]const u8, context: Context) !Self {
        return Self{ .ref = c_llvm.LLVMModuleCreateWithNameInContext(module_id.ptr, context.ref) orelse return error.LLVMError };
    }

    pub fn createExecutionEngine(self: Self) !ExecutionEngine {
        var execution_engine: ExecutionEngineRef = undefined;
        var out_error: [*c]u8 = null;

        if (c_llvm.LLVMCreateExecutionEngineForModule(@ptrCast(&execution_engine), self.ref, &out_error) == 0) {
            return ExecutionEngine{ .ref = execution_engine };
        } else {
            return error.LLVMError;
        }
    }

    pub fn getNamedFunction(self: Self, name: [:0]const u8) !ValueRef {
        return c_llvm.LLVMGetNamedFunction(self.ref, name) orelse error.LLVMError;
    }

    pub fn printToString(self: Self) !Message {
        return Message{ .message = c_llvm.LLVMPrintModuleToString(self.ref) orelse return error.LLVMError };
    }

    pub fn deinit(self: Self) void {
        c_llvm.LLVMDisposeModule(self.ref);
    }
};

pub const Function = struct {
    const Self = @This();

    ref: ValueRef,

    pub fn append_basic_block(self: Self, name: [:0]const u8) !BasicBlockRef {
        return c_llvm.LLVMAppendBasicBlock(self.ref, name.ptr) orelse return error.LLVMError;
    }
};

pub const Builder = struct {
    const Self = @This();

    ref: BuilderRef,

    pub fn positionAtEnd(self: Self, block: BasicBlockRef) void {
        c_llvm.LLVMPositionBuilderAtEnd(self.ref, block);
    }

    pub fn buildReturn(self: Self, value: ValueRef) !ValueRef {
        return c_llvm.LLVMBuildRet(self.ref, value) orelse error.LLVMError;
    }

    pub fn buildAdd(self: Self, lhs: ValueRef, rhs: ValueRef, name: [:0]const u8) !ValueRef {
        return c_llvm.LLVMBuildAdd(self.ref, lhs, rhs, name) orelse error.LLVMError;
    }

    pub fn buildSub(self: Self, lhs: ValueRef, rhs: ValueRef, name: [:0]const u8) !ValueRef {
        return c_llvm.LLVMBuildSub(self.ref, lhs, rhs, name) orelse error.LLVMError;
    }

    pub fn buildMul(self: Self, lhs: ValueRef, rhs: ValueRef, name: [:0]const u8) !ValueRef {
        return c_llvm.LLVMBuildMul(self.ref, lhs, rhs, name) orelse error.LLVMError;
    }

    pub fn buildSDiv(self: Self, lhs: ValueRef, rhs: ValueRef, name: [:0]const u8) !ValueRef {
        return c_llvm.LLVMBuildSDiv(self.ref, lhs, rhs, name) orelse error.LLVMError;
    }
};

pub const ExecutionEngine = struct {
    const Self = @This();

    ref: ExecutionEngineRef,

    pub fn runFunction(self: Self, func: ValueRef) !GenericValueRef {
        return c_llvm.LLVMRunFunction(self.ref, func, 0, null) orelse error.LLVMError;
    }

    pub fn runFunctionAsMain(self: Self, func: ValueRef) i32 {
        const args = [_][:0]const u8{"main"};
        const env = [_][:0]const u8{};
        return @intCast(c_llvm.LLVMRunFunctionAsMain(self.ref, func, 1, @ptrCast((&args).ptr), @ptrCast((&env).ptr)));
    }
};

pub const Message = struct {
    const Self = @This();

    message: [*c]u8,

    pub fn deinit(self: Self) void {
        c_llvm.LLVMDisposeMessage(self.message);
    }
};
