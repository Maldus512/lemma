# Lemma Compiler 

Side project to learn [Zig](https://ziglang.org/) and programming language development. Lemma is supposed to be a purely functional, statically typed programming language.

## Structure

The project is split into submodules at `src/`. The compilation pipeline is straightforward, with each layer relying on the previous one in the order `lexer` > `parser` > `sema` > `codegen`.

## Building

There is no entry point for the compiler just yet; everything is implemented with unit tests (`test.zig` files).\

Lemma aims to use LLVM as a backend, and linking it with `build.zig` isn't straightforward. Assuming a custom installation (I'm currently working with llvm-20), other than llvm utilities being present on `PATH` the environment variable `LEMMA_LLVM_PATH` should be provided with the path to the installation directory in order to link the static libraries. Additionally, since [Zig doesn't support stdc++ linking yet](https://github.com/ziglang/zig/issues/3936), the static `libstdc++.a` library should be passed with the `LEMMA_LIBSTDCPP_PATH`. Both paths can be passed to `zig build` directly, like so:

```bash
$ zig build -Dllvm_path="/home/maldus/Local/llvm-20/" -Dlibstdcpp_path="/usr/lib/gcc/x86_64-linux-gnu/12/libstdc++.a" test --summary all
Build Summary: 4/4 steps succeeded; 16/16 tests passed
test success
├─ run test 16 passed 22ms MaxRSS:48M
│  └─ zig test Debug native cached 16ms MaxRSS:38M
└─ install test cached
   └─ zig test Debug native (reused)
```

## TODO

 - [x] Parsing 
 - [x] Function definition and invocation
 - [x] Pipe operator
 - [x] Builtin arithmetic
 - [x] Automatic type inference
 - [x] Link with LLVM
 - [ ] Reify generic function calls
 - [ ] Codegen
 - [ ] let-in construct
 - [ ] Improve codebase by using Zig's module system
 - [ ] Consider whether to switch to scanning tokens on demand
 - [ ] Use `MultiArrayList`
