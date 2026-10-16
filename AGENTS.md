# sa_plugin_cpp — agent notes

- Zig **0.17.0 only**. Do not use system zig 0.14.1.
  `/tmp/opencode/zig-x86_64-linux-0.17.0/zig` (official tarball).
- Reference implementation: `sa_plugin_sla` branch `0.17`
  (`git show origin/0.17:<path>`); migration notes at
  `sa_plugin_sla@0.17:docs/zig_0.17_migration_cn.md`.
- 0.17 idioms used here: `main(init: std.process.Init)`,
  `std.array_list.Managed(T)`, `*std.Io.Writer`, `std.Io.Dir.cwd()`,
  `TestOptions.filters`, no `b.sysroot`/`b.args`/`std.io`/`std.fs.Dir`.
- `zig build` / `zig build test` — long builds: run with `nohup … &`, poll.
- C++ subset status: see README §v0.1. Out-of-subset ⇒ explicit compile
  error, never silent fallback.
- Plugin install: `SA_PLUGIN_DEV=1 sa plugin install --dev .`
