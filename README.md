# zig-todo

用 Zig 实现的轻量本地 Todo CLI。

当前进度：**P2 完成**（v1：优先级 / 标签 / edit / show / `--json` / clear）。设计文档见 [`docs/`](./docs/README.md)。

## 要求

- Zig **0.16.0+**（见 `build.zig.zon` 的 `minimum_zig_version`）

## 构建与运行

```bash
zig build
./zig-out/bin/zig-todo --help

DATA=/tmp/zig-todo-demo
./zig-out/bin/zig-todo --data-dir "$DATA" add "写文档" -p high -t docs -t cli
./zig-out/bin/zig-todo --data-dir "$DATA" list --priority high --tag docs
./zig-out/bin/zig-todo --data-dir "$DATA" edit 1 -d "写产品与架构文档"
./zig-out/bin/zig-todo --data-dir "$DATA" list --json
./zig-out/bin/zig-todo --data-dir "$DATA" clear --done

zig build test
```

## 命令速查

| 命令 | 说明 |
| --- | --- |
| `add "<text>" [-p pri] [-t tag]...` | 新增 |
| `list` / `ls` | 列表（默认可 open） |
| `list --status/--priority/--tag` | 组合过滤 |
| `show <id>` | 详情 |
| `edit <id> [-d text] [-p pri] [-t tag]...` | 编辑 |
| `done` / `undone <id>` | 完成 / 取消完成 |
| `rm` / `delete <id>` | 删除 |
| `clear --done` | 清理已完成 |
| `--json` | JSON 输出 |
| `--data-dir` / `ZIG_TODO_DATA_DIR` | 数据目录 |

默认数据文件（macOS）：`~/Library/Application Support/zig-todo/todos.json`。

## 文档

| 文档 | 说明 |
| --- | --- |
| [产品设计](./docs/01-产品设计文档.md) | 功能范围与命令体验 |
| [技术架构](./docs/02-技术架构设计.md) | 分层与模块设计 |
| [开发计划](./docs/03-开发优先级计划.md) | P0–P4 优先级 |
| [数据模型](./docs/04-数据模型设计.md) | JSON schema |
