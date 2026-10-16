# sa_plugin_cpp

C++ (C++17 subset) → Safe ASM (SA) compiler plugin. Mirrors the structure of
`sa_plugin_sla` (see its `0.17` branch), but the frontend parses C++ instead
of Sla and emits SA text.

> v0.1.0 — minimal viable frontend. Emits SA text only (no direct-SAB path
> yet); the API shape (`plugin_api`, descriptor ABI, CLI verbs) intentionally
> matches `sa_plugin_sla@0.17` so a future SAB backend can slot in.

## Toolchain

**Zig 0.17.0 only** (`minimum_zig_version = "0.17.0"`). Zig 0.14.x cannot
compile this repo (0.17 removed `std.io`/`b.sysroot`/`std.ArrayList` managed
API, `b.args`, `TestOptions.filter`, …). Official tarball:

```bash
mkdir -p /tmp/opencode
curl -L -o /tmp/opencode/zig-0.17.tar.xz \
  https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz
tar -xf /tmp/opencode/zig-0.17.tar.xz -C /tmp/opencode/
export PATH=/tmp/opencode/zig-x86_64-linux-0.17.0:$PATH
```

## Build / test

```bash
zig build            # libcpp.so + cpp CLI + lib/sap.json under zig-out/
zig build test       # unit tests (lexer/parser/codegen/leakcheck, no output = green)
./zig-out/bin/cpp build demos/basic/01_hello/main.cpp --out /tmp/hello.sa
```

`sci` must be on its `0.17` branch for any SA verification
(`sa check /tmp/hello.sa`); this repo itself has no sci dependency.

## Demos & acceptance

`demos/basic/01..26` mirror the `sa_plugin_sla` demo conventions
(`main.cpp` + `expected.stdout` + reviewed `main.sa` + `README.md`).
`sweep.sh` enforces the whole chain per demo
(cpp build → committed `main.sa` in sync → `sa check` → run → diff):

```bash
sh tools/sweep.sh                 # js backend (default)
BACKEND=exe sh tools/sweep.sh    # native backend (needs LLVM-built sa)
REGEN=1 sh tools/sweep.sh        # refresh committed main.sa files
```

Current acceptance: **255/255 pass on both `js` and `exe` backends**
(26 basic + 225 tsgosa rule-corpus ports + 4 refusal demos),
plus `zig build test` green (17 unit tests + 11 leakcheck tests).

Known backend divergence we pin in lowering (see `demos/tsgosa/PORTING.md`
and code comments): `i32` shifts wrap to 32 bits on js but stay wide on
interp/llvm, so every i32 `shl` is emitted with a portable
`shl-32/ashr-32` wrap sandwich (idempotent on all backends).

## Compile-time leak check

`cpp check` / `cpp build` run a path-sensitive, alias-aware leak analysis
(`src/leakcheck.zig`, details in `docs/leakcheck_cn.md`): every `new` must
be freed on all paths reaching an exit, `new[]`/`delete[]` must pair,
overwrites/early-returns/loop-carried allocations are diagnosed with C++
source lines. Out-of-subset code fails with an explicit compile
error — never silently miscompiled.

## Usage

```bash
sa cpp init /tmp/cpp_app        # minimal project skeleton
sa cpp check /tmp/cpp_app/src/main.cpp
sa cpp build /tmp/cpp_app/src/main.cpp --out /tmp/main.sa
sa cpp build-exe /tmp/cpp_app/src/main.cpp -o /tmp/main   # via host `sa`
```

## v0.1 language subset (honest list)

Supported: free functions (`int`/`long`/`float`/`double`/`bool`/`char`/
`void`, pointers, `const`-stripped params); locals with init, assignment +
compound assignment, prefix/postfix `++`/`--`; `if`/`else`, `while`,
`do`-`while`, `for(;;)`, range-`for` over fixed arrays, `switch` (lowered to
an if-chain), `return`/`break`/`continue`; arithmetic/comparison/logical/
ternary expressions, calls, `new`/`delete`; `struct`/`class` POD fields +
methods (`this->f`, `obj.m(args)` → `Class_m(obj, …)`); fixed arrays
`T a[N]` + indexing; `const char*` literals; `std::cout <<` for integers,
booleans, string literals and `std::endl`; `namespace` flattening;
`#include` lines skipped.

Not yet: templates, inheritance, exceptions, lambdas, `std::vector` /
`std::string`, user constructors with parameters, operator overloading,
preprocessor conditionals, unsigned/signed-exact arithmetic (all integers
lower as signed). Out-of-subset code fails with an explicit error naming
the construct — never silently miscompiled.

## Layout

```
src/plugin_api.zig   plugin ABI (same shape as sla@0.17)
src/cpp_rt.zig       process-wide Io + env (same role as sla_rt.zig)
src/lexer.zig        C++17-subset tokenizer
src/parser.zig       translation unit → AST
src/codegen.zig      AST → SA text
src/plugin_compile.zig  file-level compile entry points
src/plugin_commands.zig `cpp …` verbs
src/plugin_skills.zig   skill table
src/plugin.zig       descriptor + C ABI
src/local_cli.zig    standalone `cpp` binary
```
