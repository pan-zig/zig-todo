# zig-todo

用 Zig 实现的轻量本地 Todo CLI。

当前进度：**P3 完成**（原子写、CI、体验打磨）。可作为个人日常使用版本。

## 要求

- Zig **0.16.0+**（见 `build.zig.zon` 的 `minimum_zig_version`）

## 安装与构建

```bash
git clone <repo-url> zig-todo
cd zig-todo
zig build
# 产物：./zig-out/bin/zig-todo

# 可选：安装到前缀
zig build -p ~/.local
# 然后确保 ~/.local/bin 在 PATH 中
```

发布构建：

```bash
zig build -Doptimize=ReleaseFast
```

## 快速开始

```bash
zig-todo add "写文档" -p high -t docs
zig-todo list
zig-todo done 1
zig-todo list --status all --json
```

开发/测试时建议隔离数据目录：

```bash
export ZIG_TODO_DATA_DIR=/tmp/zig-todo-demo
# 或
zig-todo --data-dir /tmp/zig-todo-demo add "demo"
```

## 数据位置

| 优先级 | 来源 |
| --- | --- |
| 1 | `--data-dir <path>` |
| 2 | 环境变量 `ZIG_TODO_DATA_DIR` |
| 3 | `$XDG_DATA_HOME/zig-todo` |
| 4 | macOS：`~/Library/Application Support/zig-todo` |
| 5 | 其它 Unix：`~/.local/share/zig-todo` |

文件：

- `todos.json` — 主数据（原子写）
- `todos.json.bak` — 上一次成功保存的快照

## 命令速查

| 命令 | 说明 |
| --- | --- |
| `add "<text>" [-p pri] [-t tag]...` | 新增 |
| `list` / `ls` | 列表（默认 open） |
| `list --status/--priority/--tag` | 组合过滤 |
| `show <id>` | 详情 |
| `edit <id> [-d text] [-p pri] [-t tag]...` | 编辑（`-d` = 改描述） |
| `done` / `undone <id>` | 完成 / 取消完成 |
| `rm` / `delete <id>` | 删除 |
| `clear --done` | 清理已完成 |
| `--json` / `-q` | JSON 输出 / 安静模式 |

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 业务错误（未找到、校验失败） |
| 2 | 用法错误 |
| 3 | IO / 损坏数据等内部错误 |

## 测试

```bash
zig build test
```

CI：GitHub Actions 在 Linux / macOS 上执行 `zig build` 与 `zig build test`。

## 文档

| 文档 | 说明 |
| --- | --- |
| [产品设计](./docs/01-产品设计文档.md) | 功能范围与命令体验 |
| [技术架构](./docs/02-技术架构设计.md) | 分层与模块设计 |
| [开发计划](./docs/03-开发优先级计划.md) | P0–P4 优先级 |
| [数据模型](./docs/04-数据模型设计.md) | JSON schema |
