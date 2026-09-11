//! zig-todo 的构建脚本。
//!
//! `zig build` 并不会「立刻执行」这里的代码去编译；
//! 而是先调用 `build`，让我们在内存里描述一张「构建图」（有哪些产物、步骤、依赖），
//! 再由 Zig 的 build runner 按需并行执行。
//!
//! 常用命令：
//!   zig build                 → 编译并安装到 zig-out/bin/zig-todo
//!   zig build run -- version  → 编译后运行，并把 `--` 后的参数传给程序
//!   zig build test            → 跑库模块 + 可执行模块里的 test
//!   zig build -Doptimize=ReleaseFast

const std = @import("std");

/// 构建入口：只负责「声明」构建图，不直接跑编译器。
/// `b` 是 Build DSL，用来注册模块、可执行文件、步骤和它们之间的依赖。
pub fn build(b: *std.Build) void {
    // -------------------------------------------------------------------------
    // 1. 标准选项（用户可通过命令行覆盖）
    // -------------------------------------------------------------------------
    // -Dtarget=...     交叉编译目标，例如 x86_64-windows；默认为本机
    // -Doptimize=...   Debug | ReleaseSafe | ReleaseFast | ReleaseSmall；默认 Debug
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------------------------
    // 2. 库模块 zig_todo（业务逻辑，可被 exe / test / 外部包 import）
    // -------------------------------------------------------------------------
    // addModule：向「本 package 的对外模块表」注册一个可导入模块。
    // 源码里用 `@import("zig_todo")` 即可引用；根文件是 src/root.zig。
    // 对外可见的声明必须从 root.zig 再导出（re-export）。
    const mod = b.addModule("zig_todo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        // 库模块此处可不强制 optimize；测试时会用到 .target
    });

    // -------------------------------------------------------------------------
    // 3. 可执行文件 zig-todo（CLI 入口）
    // -------------------------------------------------------------------------
    // 可执行文件必须有自己的 root module，且其中要有 `main`。
    // 我们把 CLI（main.zig）与库（root.zig）拆开：
    //   - main.zig：解析参数、打印、退出码
    //   - root.zig：domain / storage / cli 等可复用逻辑
    //
    // createModule：创建「仅内部使用」的模块（不对外暴露包名）。
    // imports：声明该模块里可用的 `@import("名字")` 映射。
    const exe = b.addExecutable(.{
        .name = "zig-todo", // 安装后的二进制名：zig-out/bin/zig-todo
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                // 在 main.zig 中：const zig_todo = @import("zig_todo");
                .{ .name = "zig_todo", .module = mod },
            },
        }),
    });

    // -------------------------------------------------------------------------
    // 4. 默认步骤：安装产物
    // -------------------------------------------------------------------------
    // `zig build`（无子命令）会跑「默认 install 步骤」。
    // installArtifact 声明：把 exe 拷到安装前缀（默认 zig-out/，可用 -p 改）。
    b.installArtifact(exe);

    // -------------------------------------------------------------------------
    // 5. 自定义步骤 run：编译并运行
    // -------------------------------------------------------------------------
    // b.step：注册顶层步骤名，会出现在 `zig build --help` 与 IDE 侧栏。
    // addRunArtifact：构建图里加一个「运行该产物」的节点。
    const run_step = b.step("run", "Run zig-todo");
    const run_cmd = b.addRunArtifact(exe);

    // run 步骤 → 依赖「真正执行程序」的 run_cmd
    run_step.dependOn(&run_cmd.step);
    // 先走完 install，再从安装目录运行（而不是直接跑 cache 里的临时产物）
    run_cmd.step.dependOn(b.getInstallStep());

    // 支持：zig build run -- version
    // `--` 后面的参数由 build runner 放进 b.args，再转发给程序。
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // -------------------------------------------------------------------------
    // 6. 单元测试（库模块 + 可执行模块各一套）
    // -------------------------------------------------------------------------
    // Zig 的 test 可执行文件一次只测「一个」root module，所以拆成两个：
    //   - mod_tests：跑 src/root.zig 及其拉进来的模块里的 test（如 cli/args.zig）
    //   - exe_tests：跑 src/main.zig 里的 test（若有）
    //
    // addTest：编译带 test 的可执行文件；addRunArtifact：实际跑它。

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // `zig build test`：两个测试互不依赖，runner 可并行执行。
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
