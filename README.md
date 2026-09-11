# zig-todo

用 Zig 实现的轻量本地 Todo CLI。

当前进度：**P0 脚手架完成**（可构建、可查看帮助/版本）。设计文档见 [`docs/`](./docs/README.md)。

## 要求

- Zig **0.16.0+**（见 `build.zig.zon` 的 `minimum_zig_version`）

## 构建与运行

```bash
zig build
./zig-out/bin/zig-todo --help
./zig-out/bin/zig-todo version

# 或
zig build run -- version
zig build test
```

## 当前可用命令

| 命令 / 旗标 | 说明 |
| --- | --- |
| `help` / `-h` / `--help`（默认） | 显示帮助 |
| `version` / `-V` / `--version` | 打印版本 |

`add` / `list` / `done` / `rm` 等将在 **P1** 实现。

## 文档

| 文档 | 说明 |
| --- | --- |
| [产品设计](./docs/01-产品设计文档.md) | 功能范围与命令体验 |
| [技术架构](./docs/02-技术架构设计.md) | 分层与模块设计 |
| [开发计划](./docs/03-开发优先级计划.md) | P0–P4 优先级 |
| [数据模型](./docs/04-数据模型设计.md) | JSON schema |

## 源码布局（P0）

```text
src/
  main.zig          # CLI 入口
  root.zig          # 库根
  cli/              # 参数、输出、退出码
  domain/           # P1+ 占位
  storage/          # P1+ 占位
  app.zig / util/   # P1+ 占位
```
