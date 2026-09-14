# zig-todo

用 Zig 实现的轻量本地 Todo CLI。

当前进度：**P1 MVP 完成**（`add` / `list` / `done` / `rm` + JSON 持久化）。设计文档见 [`docs/`](./docs/README.md)。

## 要求

- Zig **0.16.0+**（见 `build.zig.zon` 的 `minimum_zig_version`）

## 构建与运行

```bash
zig build
./zig-out/bin/zig-todo --help

# 指定数据目录（推荐开发/测试时使用）
./zig-out/bin/zig-todo --data-dir /tmp/zig-todo-demo add "first task"
./zig-out/bin/zig-todo --data-dir /tmp/zig-todo-demo list
./zig-out/bin/zig-todo --data-dir /tmp/zig-todo-demo done 1

zig build test
```

## 命令

| 命令 | 说明 |
| --- | --- |
| `add "<text>"` | 新增待办 |
| `list` / `ls` | 列表（默认仅 open） |
| `list --status all` | 全部状态 |
| `done <id>` | 标记完成 |
| `rm` / `delete <id>` | 删除 |
| `version` / `-V` | 版本 |
| `help` / `-h` | 帮助 |

全局：`--data-dir <path>`，或环境变量 `ZIG_TODO_DATA_DIR`。

默认数据目录（macOS）：`~/Library/Application Support/zig-todo/todos.json`。

## 文档

| 文档 | 说明 |
| --- | --- |
| [产品设计](./docs/01-产品设计文档.md) | 功能范围与命令体验 |
| [技术架构](./docs/02-技术架构设计.md) | 分层与模块设计 |
| [开发计划](./docs/03-开发优先级计划.md) | P0–P4 优先级 |
| [数据模型](./docs/04-数据模型设计.md) | JSON schema |
