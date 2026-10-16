# 编译期内存泄漏检查（`cpp check` / `cpp build` 自带）

理论：泄漏检查 = CFG 可达性 + alloc/free 配对。SA 验证器已有运行时半壁
（`MemoryLeak` / `UseAfterMove` trap）；这里是编译时半壁：出错直接给
C++ 源码行号，不生成 SA。

实现位置：`src/leakcheck.zig`，跑在 parse 之后、codegen 之前，
 intraprocedural，路径敏感，函数内全路径覆盖。

## 规则（v0.1）

- `new`（含 `new[]`）产生 obligation，必须在同一函数所有到达出口的
  路径上被 `delete`（`delete[]` 配对检查）消耗，否则 `LeakError`。
- `delete` 两次 = double delete；`new[]` 配 `delete`（或反之）= mismatch。
- `p = new` 覆盖一个 live 指针 = 泄漏旧分配（别名覆盖）。
- `return` 时仍 live（除被 return 自身转移出去的）= 泄漏（提前 return 同理）。
- `q = p` 合并别名集：经任一名字 `delete` 即释放全集；全集无人释放 = 泄漏。
- 块/循环体结束时 live 的块内分配 = 泄漏（出作用域即不可达）。
- `new` 直接做 call 实参且不绑定 = 泄漏（无过程间证明 callee 会 free）。
- `return p` 把所有权转移出函数（调用方责任，过程间检查在 roadmap）。

## 8 种泄漏对照（需求原文 → 本实现）

| 需求类型 | 本仓落点 |
|---|---|
| new 不 delete / 提前 return / 循环 leak | ✅ 路径敏感 walk 全覆盖 |
| 别名覆盖 `p=new; p=new` | ✅ 覆盖即报旧 site 行号 |
| `q=p; delete q` | ✅ 别名集，一次释放全集 |
| malloc/delete 混用 | 子集无 malloc；做 `new[]/delete[]` 配对 |
| 异常路径 | N/A：`throw/try` 在 parse 期直接拒绝 |
| 过程间/工厂返回 | `return p` 放行转移；调用方检查 roadmap |
| UE5 NewObject | N/A（无 UE5；配对规则表架构已预留位置） |

## 已知保守点（宁可误报，不漏报；文档化）

- 跨分支条件相关（`if (c) new; if (c) delete` 视为两条独立路径，
  合并后按 live-on-any-path 处理，一般仍判对；极端相关分支可能误报）。
- 未知来源指针（工厂返回、参数）的 `delete` 直接放行（不证明错不错报）。

## 关闭

暂无开关：泄漏即编译失败（对应需求 `exit=1` 语义）。
如需宽松，roadmap：`--leak=lenient|off`。
