# zig-todo 源码导读与 Zig 知识点复习

面向：刚学完 Zig 基础、想通过真实项目反哺复习的读者。  
配套总览可在 Cursor 里打开 Canvas：[zig-todo 学习导图](/Users/panfeng/.cursor/projects/Users-panfeng-ZigProjects-pan-zig-zig-todo/canvases/zig-todo-learning-guide.canvas.tsx)。

---

## 0. 先建立心智模型（5 分钟）

这个项目做一件事：**本地 Todo CLI**，数据落在 JSON 文件里。

分层（从上到下，**只允许向下依赖**）：

```text
┌─────────────────────────────────────┐
│  main.zig     组装进程、退出码、打印   │
├─────────────────────────────────────┤
│  cli/         解析 argv → 命令意图     │
│  app.zig      用例：load → 改 → save  │
├─────────────────────────────────────┤
│  domain/      纯业务：Todo / 过滤规则  │  ← 不碰文件、不碰 stdout
├─────────────────────────────────────┤
│  storage/     JSON、原子写、锁、路径   │
│  util/        时间、日期、错误集合     │
└─────────────────────────────────────┘
```

**为什么这样分？**

| 层 | 可以依赖 | 禁止 |
| --- | --- | --- |
| domain | 仅 std / 自己 | 文件系统、CLI 字符串 |
| storage | domain + util | 解析 `--json`、打印表格 |
| app | domain + storage | 直接 `std.process.exit` |
| cli / main | 全部 | —（最外层） |

复习点：这就是「依赖倒置 / 分层」在小项目里的落地——**业务规则不绑死在 IO 上**，单测才好写。

---

## 1. 文件结构（每个文件一句话）

```text
zig-todo/
├── build.zig                 # 描述「构建图」：库 + exe + test
├── build.zig.zon             # 包元数据（zig 版本等）
├── README.md
├── docs/                     # 产品/架构/计划/数据模型（设计文档）
└── src/
    ├── main.zig              # 进程入口（exe root）
    ├── root.zig              # 库入口：re-export 各模块
    ├── version.zig           # "0.1.0"
    ├── app.zig               # 用例编排
    ├── cli.zig / domain.zig / storage.zig / util.zig   # 桶文件（再导出子模块）
    ├── cli/
    │   ├── commands.zig      # Command = union(enum) …
    │   ├── args.zig          # argv → Parsed
    │   ├── output.zig        # 帮助 / 表格 / JSON 输出
    │   └── exit_codes.zig    # 0/1/2/3
    ├── domain/
    │   ├── todo.zig          # 实体 + 校验 + 所有权
    │   ├── list.zig          # 集合操作、EditPatch、import
    │   ├── filter.zig        # list 过滤谓词
    │   └── id.zig            # next_id 自愈
    ├── storage/
    │   ├── store.zig         # JsonFileStore 核心
    │   ├── paths.zig         # 数据目录解析
    │   ├── atomic_file.zig   # 原子写 + .bak
    │   ├── file_lock.zig     # todos.lock
    │   └── migrate.zig       # schema 版本
    └── util/
        ├── time.zig          # Io → Unix 秒
        ├── date.zig          # YYYY-MM-DD ↔ Unix
        └── err.zig           # 共享错误类型（辅助）
```

### 构建：库 / 可执行文件拆开

`build.zig` 里有两个「根」：

| 根 | 文件 | 作用 |
| --- | --- | --- |
| 库模块 `zig_todo` | `src/root.zig` | 业务；可被测试、被 exe import |
| 可执行文件 | `src/main.zig` | 只有 `main`；`@import("zig_todo")` |

复习点：

- `b.addModule`：对外可 import 的模块名  
- `b.createModule` + `imports`：给 exe 声明「`@import("zig_todo")` 指向谁」  
- `zig build test` 会分别测库 root 和 exe root（Zig 一次只能测一个 root）

---

## 2. 进程入口与 Zig 0.16 运行时

### 2.1 `main` 签名变了

Zig 0.16 推荐：

```zig
pub fn main(init: std.process.Init) !void
```

不再是「自己创建 Arena / GPA」。运行时帮你准备好：

| 字段 | 用途（本项目） |
| --- | --- |
| `init.arena` | **短命**分配：argv 切片、临时错误字符串；进程结束整块丢掉 |
| `init.gpa` | **长命**分配：Todo 文本、标签、`data_dir`、JSON 缓冲 |
| `init.io` | 统一 Io：文件、stdout、时钟 |
| `init.minimal.args` | 命令行参数 |
| `init.minimal.environ` | 环境变量（给 `paths.resolveDataDir`） |

**复习：两种分配器怎么选？**

- 问自己：这块内存要活过「这次命令」吗？  
  - 否 → arena（省心，不用每个 free）  
  - 是 → gpa，并配对 `defer free` / `deinit`

### 2.2 stdout / stderr

```zig
var stdout_buffer: [8192]u8 = undefined;
var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
const stdout = &stdout_file_writer.interface;
// … 写完 …
try stdout.flush();
```

复习点：0.16 的 Writer 是**缓冲的**；不 `flush` 可能丢输出。错误信息走 stderr，成功表格走 stdout——方便脚本把 stdout 接到 `jq`。

### 2.3 顶层分流

```text
parse(argv)
  ├─ help / version     → 打印，exit 0
  ├─ usage / unknown    → stderr，exit 2
  └─ 其它命令           → runStoreCommand（需要数据目录 + Store）
```

`mapError` 把 Domain/Storage 错误映射成退出码：

| 码 | 含义 | 例 |
| --- | --- | --- |
| 0 | 成功 | |
| 1 | 业务错误 | NotFound、EmptyText |
| 2 | 用法错误 | 缺参数、未知命令 |
| 3 | 内部/IO | CorruptData、IoError |

---

## 3. 一次 `add` 的完整调用链（最重要）

以：

```bash
zig-todo --data-dir /tmp/demo add "写文档" -p high -t docs --due 2026-12-31
```

为准，逐步跟：

```text
1. main
   args = init.minimal.args.toSlice(arena)
   parsed = cli.args.parse(args)

2. args.parse
   全局 flag：--data-dir=/tmp/demo
   子命令名 "add"
   parseAdd：text="写文档", priority=high, tags=["docs"], due_at=Unix(2026-12-31)
   → Command.add { … }

3. runStoreCommand
   data_dir = paths.resolveDataDir(gpa, environ, "/tmp/demo")
   store = JsonFileStore.init(gpa, io, data_dir)
   now = app.now(io)          // Io.Clock → i64

4. app.add(&store, text, now, CreateOptions{…})
   list = store.load()        // 见 §5：锁 → 读 JSON → TodoList
   defer list.deinit()
   item = list.addNew(…)      // domain：校验 + 拷贝字符串
   id = item.id
   store.save(&list)          // 锁 → stringify → 原子写

5. main 打印 "Added #1: 写文档" 或 --json 再 load 一次打 JSON
```

**一张图记住「写路径」模板：**

```text
任何修改类命令 ≈
  load（带锁）→ 改内存中的 TodoList → save（带锁 + 原子写）
```

只读命令（`list` / `show` / `export` 到 stdout）只 `load`，不 `save`。

---

## 4. CLI：意图建模（Tagged Union）

### 4.1 `Command` 是什么

```zig
pub const Command = union(enum) {
    help,
    version,
    add: AddArgs,
    list: ListArgs,
    // …
    @"export": ExportArgs,  // export 是关键字，必须 @"…"
    import: PathArgs,
    unknown: []const u8,
    usage: []const u8,
};
```

复习点：

1. **`union(enum)` = 带标签的联合体**：同一时间只有一种命令有效。  
2. `switch (parsed.command)` 必须**穷尽**所有标签（编译器帮你查漏）。  
3. Zig **关键字**不能当字段名：`export` → `@"export"`。

### 4.2 手工 parse，不用 clap

`args.zig` 从 `argv[1]` 扫全局 flag，再按子命令名分发。标签存在栈上的 `TagBuf`（固定上限 16），**不拥有字符串**——指针仍指向 argv。

真正持久化时，`todo.create` 会 `allocator.dupe` 拷贝。

复习点：**「借用」vs「拥有」**

| 阶段 | text / tags 谁拥有？ |
| --- | --- |
| parse 之后 | argv / 静态 `join_buf`（借用） |
| `Todo` 进 List 后 | gpa（拥有，要 deinit） |

### 4.3 多词标题怎么拼

`add hello world` 会把 `hello`、`world` 拼成 `"hello world"`。  
实现用静态 `[512]u8` + `@memcpy`，**没用** `std.io.Writer`（0.16 Writer 变化大，解析层避免引入 Io）。

代价：非重入、有长度上限——对单线程 CLI 可接受。这是**工程权衡**，不是「唯一正确写法」。

---

## 5. Domain：所有权与规则

### 5.1 `Todo` 字段

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `id` | `u64` | 唯一正整数 |
| `text` | `[]const u8` | 标题（堆上拷贝） |
| `status` | `open \| done` | |
| `priority` | `low \| medium \| high` | |
| `tags` | `[]const []const u8` | 小写、去重 |
| `created_at` / `updated_at` | `i64` | Unix 秒 |
| `completed_at` | `?i64` | 可选 |
| `due_at` | `?i64` | 可选截止日期 |

### 5.2 创建时的 `errdefer`（防泄漏）

```zig
const owned_text = try copyText(allocator, text);
errdefer allocator.free(owned_text);

const owned_tags = try normalizeTags(allocator, options.tags);
errdefer freeTags(allocator, owned_tags);

return .{ .text = owned_text, .tags = owned_tags, … };
```

复习：

- `try` 失败会跳走；`errdefer` 只在**错误路径**执行。  
- 成功返回后，所有权交给调用方（`TodoList`），由 `Todo.deinit` 释放。

### 5.3 Unmanaged `ArrayList`（0.x 常见写法）

```zig
items: std.ArrayList(Todo) = .empty;
try self.items.append(self.allocator, item);
self.items.deinit(self.allocator);
```

分配器**不存在结构体里**，每次方法传入。好处：同一 list 可换 allocator；坏处：容易忘传。

### 5.4 `EditPatch` / `DuePatch`

```zig
pub const DuePatch = union(enum) {
    clear,
    set: i64,
};

pub const EditPatch = struct {
    text: ?[]const u8 = null,
    priority: ?Priority = null,
    tags: ?[]const []const u8 = null, // non-null = 整表替换
    due_at: ?DuePatch = null,
};
```

复习：`?T` 的三态在「编辑」里很有用：

- `null` = 不改  
- `Some(value)` = 改成该值（对 tags，空切片 = 清空标签）  
- due 用 `DuePatch` 区分「不改」和「改成 null」

### 5.5 `Filter` 与 `matches`

AND 组合：`status` ∩ `priority?` ∩ 每个 `tag` ∩ `overdue_before?`。  
`isOverdue`：仅 `open` 且 `due_at < now`。

---

## 6. Storage：从内存到磁盘

### 6.1 数据目录优先级

```text
--data-dir
  → ZIG_TODO_DATA_DIR
  → $XDG_DATA_HOME/zig-todo
  → 平台默认（macOS Application Support / Linux .local/share / Windows APPDATA）
  → 兜底 .zig-todo
```

文件：

| 文件 | 作用 |
| --- | --- |
| `todos.json` | 主库（schema v2） |
| `todos.json.bak` | 上次成功写的快照 |
| `archive.json` | 归档的 done 项 |
| `todos.lock` | 建议性排他锁 |

### 6.2 文件锁

```zig
FileLock.acquire → createFileAbsolute(..., .{ .lock = .exclusive })
defer lock.release()
```

`load` / `save` 各自加锁；`import` / `archive` 在**同一把锁**里完成「读-改-写」，避免中间被别人插队。

复习：这是**协作式**锁（advisory）。同一程序多进程有效；不能防恶意进程忽略锁。

### 6.3 原子写（崩溃安全）

`atomic_file.writeAtomicReplace` 大致步骤：

1. 若目标存在 → `copyFile` 到 `*.bak`  
2. `createFileAtomic` 写临时文件 + flush  
3. `atomic.replace` 瞬间替换目标名  

复习：直接 `open + write` 主文件，进程被杀会留下半截 JSON → `CorruptData`。原子替换把「可见的新文件」变成一步。

### 6.4 JSON Document

落盘形状：

```json
{
  "version": 2,
  "next_id": 4,
  "todos": [ { "id": 1, "text": "...", "due_at": null, ... } ]
}
```

读：

```zig
std.json.parseFromSlice(Document, allocator, bytes, .{
    .allocate = .alloc_always,
    .ignore_unknown_fields = true,
})
```

写：

```zig
std.json.Stringify.valueAlloc(allocator, doc, .{ .whitespace = .indent_2 })
```

**v1 → v2**：只加了可选 `due_at`；缺字段默认 `null`，下次 save 写成 version=2。

### 6.5 导出 vs 导入（格式不对称，故意的）

| | 格式 |
| --- | --- |
| `export` | **JSON 数组** `[ {...}, ... ]`（脚本友好） |
| 主库 | Document（带 version / next_id） |
| `import` | 两种都接受：先试数组，再试 Document |

导入会**重新分配 id**（避免和现有 id 冲突）。

---

## 7. 其它命令的调用链（对照表）

| 命令 | 调用链要点 |
| --- | --- |
| `list` | load → 构造 `Filter` → 打印（不过滤则改盘） |
| `show` | load → `findById` → 详情 / JSON |
| `done` / `undone` | load → mark* → save |
| `edit` | load → `EditPatch` → save |
| `rm` | load → `removeById` → **调用方** `removed.deinit` → save |
| `clear --done` | load → `clearDone`（边删边 deinit）→ save |
| `archive --done` | 锁内：load → `takeDone` → 追加 `archive.json` → save 主库 |
| `export [path]` | load → stringify 数组 → 文件或 stdout |
| `import path` | 锁内：读文件 → 解析 → 多次 `addNew` → save |

---

## 8. 建议的「带着问题读代码」路径

按这个顺序打开文件，每文件只盯一个问题：

| 顺序 | 文件 | 带着什么问题读 |
| --- | --- | --- |
| 1 | `build.zig` | 库和 exe 怎么连上的？`zig build test` 测谁？ |
| 2 | `main.zig` | arena / gpa / io 各干什么？错误怎么变退出码？ |
| 3 | `cli/commands.zig` | 为什么用 union？`@"export"` 是什么？ |
| 4 | `cli/args.zig` | 全局 flag 和子命令 flag 怎么分开扫？ |
| 5 | `domain/todo.zig` | `errdefer` 防的是哪次失败？谁 free text？ |
| 6 | `domain/list.zig` | `EditPatch` 的 null 语义？`takeDone` 所有权？ |
| 7 | `app.zig` | 为什么几乎每个函数都是 load→改→save？ |
| 8 | `storage/store.zig` | 锁包住了哪些操作？import 为何重新分配 id？ |
| 9 | `storage/atomic_file.zig` | 为什么先 bak 再 atomic replace？ |
| 10 | `util/date.zig` | 日期为什么存 Unix 秒而不是字符串？ |

读完后自己默写一遍 `add` 调用链；对不上再回头翻 §3。

---

## 9. Zig 知识点清单（本项目出现过）

用项目当 checklist，不会的回去查官方文档或本仓库对应文件：

### 语言核心

- [ ] `@import` / 模块拆分 / `root.zig` re-export  
- [ ] `struct` / `enum` / `union(enum)` / `@"keyword"`  
- [ ] `?T` 可选类型与 `orelse`  
- [ ] `!T` 错误联合、`try`、`catch`、`errdefer`、`defer`  
- [ ] `anyerror` 与在边界 `switch (err)` 收窄  
- [ ] 切片 `[]const u8`、`dupe`、谁拥有内存  
- [ ] `std.ArrayList` unmanaged：`.empty` + 传 allocator  
- [ ] `test "name" { … }` 与 `std.testing.allocator`（测泄漏）

### 标准库 / 0.16

- [ ] `std.process.Init`：arena、gpa、io、args、environ  
- [ ] `std.Io`：`File.Writer`、`Dir.readFileAlloc`、`createFileAtomic`  
- [ ] `std.json`：`parseFromSlice` / `Stringify.valueAlloc`  
- [ ] `std.fs.path.join`、绝对/相对路径  
- [ ] `std.fmt.bufPrint` 与缓冲区大小（太小会 `NoSpaceLeft`）  
- [ ] `builtin.os.tag` 做平台分支（paths.zig）

### 工程实践

- [ ] 分层：Domain 无 IO  
- [ ] CLI 意图用 tagged union  
- [ ] 原子写 + 备份防损坏  
- [ ] advisory 文件锁  
- [ ] schema `version` 与加法迁移  
- [ ] 退出码约定（脚本友好）  
- [ ] `build.zig` 双 root 测试  

### 本项目踩过的坑（复习加分）

1. **`export` 关键字** → 字段名写成 `@"export"`  
2. **日期 `bufPrint` 缓冲过小** → `[10]` 不够，用 `[16]`；年份用 `u32` 避免打印 `+2020`  
3. **解析层拼字符串** → 避开复杂 Writer，用手写 `@memcpy`  
4. **`addNew` 返回的 Todo** → 与 list 内共享指针，只取 `id`，不要对返回值再 `deinit`  
5. **先分配新 text 再 free 旧的** → 编辑失败时不丢数据  

---

## 10. 动手小练习（巩固）

1. 加一个命令 `count`：只打印 open / done 数量（只改 cli + app，尽量不动 store）。  
2. 给 `list` 加 `--sort id|updated`（先在 domain 排序指针切片，别改存储顺序）。  
3. 故意写坏 `todos.json`，确认退出码是 3，并看 `.bak` 是否还能救。  
4. 两个终端同时 `add`，观察锁是否让其中一个等待（或失败）。  

---

## 11. 和设计文档的对应关系

| 想了解 | 读 |
| --- | --- |
| 产品要做什么 | `docs/01-产品设计文档.md` |
| 分层与错误模型 | `docs/02-技术架构设计.md` |
| P0–P4 做了啥 | `docs/03-开发优先级计划.md` |
| JSON 长什么样 | `docs/04-数据模型设计.md` |
| **源码怎么串起来（本文）** | `docs/05-源码导读与Zig复习.md` |

当前进度：P0–P4 核心完成；完整 TUI 仍在 Backlog。
