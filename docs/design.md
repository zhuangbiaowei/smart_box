# smart_box 独立项目开发说明书

## 0. 项目名称

`smart_box`

## 1. 项目定位

`smart_box` 是一个面向 Agent 执行任务的本地可回退沙箱系统。

它的核心目标是：

> 让 Coding Agent / SmartExpert / SmartCoder 在不直接污染真实项目目录的前提下，完成文件修改、命令执行、依赖安装、实验性修复、代码生成、diff 查看、checkpoint 回滚、patch 导出等操作。

`smart_box` 不是完整 Agent，也不是聊天系统。它是一个独立的底层执行基础设施，专门解决 Agent 执行过程中的安全性、可追溯性、可回退性问题。

---

## 2. 设计原则

### 2.1 Reversible-first

所有可能改变项目状态的操作，都应该先发生在 `smart_box` 中，而不是直接发生在原项目目录中。

用户或上层 Agent 应该可以：

* 查看改了什么；
* 回滚到之前的 checkpoint；
* 放弃整个 box；
* 导出 patch；
* 在确认后将 patch 应用到真实项目。

### 2.2 Observable-first

`smart_box` 中的每一次操作都必须可观察、可记录、可审计。

至少记录：

* 操作时间；
* 操作类型；
* 执行命令；
* 工作目录；
* 标准输出；
* 标准错误；
* 退出码；
* 变更文件；
* checkpoint 信息。

### 2.3 Sandbox-first

首版不要求强安全隔离，不需要立即实现 Docker / container / seccomp 等重隔离机制。

但必须做到：

* 不直接修改原项目目录；
* 默认在复制目录或 git worktree 中执行；
* 所有变更先停留在 box 内；
* 真实项目只通过显式 `apply` 或 patch 应用来改变。

### 2.4 CLI-first

首版优先实现命令行工具。

后续 SmartExpert TUI / GUI 可以通过 CLI 或 Ruby API 调用 `smart_box`。

### 2.5 Library-ready

虽然首版提供 CLI，但内部结构应该设计成可作为 Ruby library 调用。

目标是未来可以这样使用：

```ruby
box = SmartBox::Box.create(source: ".", mode: :copy, task_id: "task-001")
box.run("bundle install")
box.checkpoint("after bundle install")
box.diff
box.rollback("cp-001")
box.export_patch("fix.patch")
```

---

## 3. 技术栈建议

首版使用 Ruby 实现。

建议项目结构：

```text
smart_box/
  bin/
    smart_box
  lib/
    smart_box.rb
    smart_box/
      version.rb
      cli.rb
      box.rb
      metadata.rb
      runner.rb
      checkpoint.rb
      diff.rb
      patch.rb
      logger.rb
      errors.rb
      modes/
        copy_mode.rb
        git_worktree_mode.rb
  spec/
  README.md
  Gemfile
  smart_box.gemspec
```

---

## 4. MVP 范围

首版只实现两种 box 模式：

1. `copy` mode
2. `git-worktree` mode

暂不实现：

* Docker / DevContainer；
* 网络访问控制；
* 权限沙箱；
* 多用户并发；
* Web UI；
* 复杂策略引擎；
* 自动安全审计。

---

## 5. 核心概念

### 5.1 Source Project

原始项目目录。

例如：

```bash
/home/user/projects/my_ruby_app
```

`smart_box` 不应该直接修改这个目录。

### 5.2 Box

一次隔离执行空间。

每个 box 对应一个任务、一次实验或一次 Agent 执行过程。

例如：

```text
.smart_box/
  boxes/
    task-001/
```

### 5.3 Checkpoint

box 内部的状态保存点。

每个 checkpoint 应该允许用户回退。

MVP 阶段可以通过 Git commit 实现 checkpoint，即在 box 内初始化一个 git 仓库，然后每次 checkpoint 做一次 commit。

### 5.4 Diff

box 当前状态相对于初始状态或某个 checkpoint 的差异。

### 5.5 Patch

从 box 导出的变更文件，用于让用户确认后应用到真实项目。

### 5.6 Command Log

box 中执行过的命令记录。

---

## 6. 推荐目录结构

在源项目根目录下生成 `.smart_box` 目录：

```text
source_project/
  .smart_box/
    config.yml
    boxes/
      task-001/
        metadata.yml
        workspace/
        logs/
          commands.log
          commands.jsonl
        patches/
          current.patch
        checkpoints/
          index.yml
```

说明：

* `workspace/` 是实际执行目录；
* `metadata.yml` 保存 box 元信息；
* `commands.log` 保存人类可读日志；
* `commands.jsonl` 保存机器可读日志；
* `patches/` 保存导出的 patch；
* `checkpoints/index.yml` 保存 checkpoint 索引。

---

## 7. Box Metadata 设计

每个 box 都应该有 `metadata.yml`。

示例：

```yaml
id: task-001
name: "fix bundler conflict"
mode: copy
source_path: "/home/user/projects/demo"
workspace_path: "/home/user/projects/demo/.smart_box/boxes/task-001/workspace"
created_at: "2026-06-05T10:30:00+08:00"
updated_at: "2026-06-05T10:45:00+08:00"
status: active

base:
  type: copy
  source_git_commit: "abc123"
  source_git_branch: "main"

checkpoints:
  - id: cp-001
    name: "initial"
    created_at: "2026-06-05T10:31:00+08:00"
    git_commit: "boxcommit001"
  - id: cp-002
    name: "after bundle install"
    created_at: "2026-06-05T10:35:00+08:00"
    git_commit: "boxcommit002"

stats:
  commands_count: 3
  changed_files_count: 2
```

---

## 8. 命令行接口设计

命令统一使用：

```bash
smart_box <command> [options]
```

### 8.1 创建 box

```bash
smart_box create --source . --id task-001 --mode copy
```

参数：

```text
--source PATH       原项目目录
--id ID             box id
--mode MODE         copy 或 git-worktree
--name NAME         可选，人类可读名称
```

行为：

1. 检查 source 是否存在；
2. 创建 `.smart_box/boxes/<id>/`；
3. 创建 workspace；
4. 在 workspace 内初始化 git；
5. 创建初始 checkpoint；
6. 写入 metadata。

输出示例：

```text
Box created:
  id: task-001
  mode: copy
  workspace: .smart_box/boxes/task-001/workspace
  checkpoint: cp-001 initial
```

---

### 8.2 查看 box 列表

```bash
smart_box list --source .
```

输出示例：

```text
ID        MODE          STATUS    UPDATED_AT
task-001  copy          active    2026-06-05 10:45
task-002  git-worktree  active    2026-06-05 11:02
```

---

### 8.3 查看 box 状态

```bash
smart_box status --id task-001
```

输出示例：

```text
Box: task-001
Mode: copy
Status: active
Workspace: .smart_box/boxes/task-001/workspace

Changed files:
  M Gemfile
  M Gemfile.lock

Checkpoints:
  cp-001 initial
  cp-002 after bundle install
```

---

### 8.4 在 box 中执行命令

```bash
smart_box run --id task-001 -- bundle install
```

行为：

1. 进入 box workspace；
2. 执行命令；
3. 捕获 stdout、stderr、exit code；
4. 写入 commands.log；
5. 写入 commands.jsonl；
6. 输出命令结果。

JSONL 示例：

```json
{"time":"2026-06-05T10:40:00+08:00","box_id":"task-001","type":"run","command":"bundle install","cwd":"workspace","exit_code":1,"stdout_path":"logs/0003.stdout.log","stderr_path":"logs/0003.stderr.log"}
```

---

### 8.5 创建 checkpoint

```bash
smart_box checkpoint --id task-001 --name "after gemfile change"
```

行为：

1. 检查 workspace 变更；
2. git add 全部变更；
3. git commit；
4. 生成 checkpoint id，例如 `cp-003`；
5. 更新 metadata。

输出示例：

```text
Checkpoint created:
  id: cp-003
  name: after gemfile change
  commit: boxcommit003
```

---

### 8.6 查看 checkpoint 列表

```bash
smart_box checkpoints --id task-001
```

输出：

```text
cp-001  initial
cp-002  after bundle install
cp-003  after gemfile change
```

---

### 8.7 回滚到 checkpoint

```bash
smart_box rollback --id task-001 --checkpoint cp-002
```

行为：

1. 检查 checkpoint 是否存在；
2. 使用 git reset --hard <checkpoint_commit>；
3. 记录 rollback 操作；
4. 更新 metadata。

输出：

```text
Rolled back:
  box: task-001
  checkpoint: cp-002
```

---

### 8.8 查看 diff

```bash
smart_box diff --id task-001
```

默认显示当前 workspace 相对于初始 checkpoint 的 diff。

也支持：

```bash
smart_box diff --id task-001 --from cp-002
smart_box diff --id task-001 --from cp-002 --to cp-003
```

---

### 8.9 导出 patch

```bash
smart_box export-patch --id task-001 --output fix.patch
```

默认导出当前状态相对于初始 checkpoint 的 patch。

输出：

```text
Patch exported:
  fix.patch
```

---

### 8.10 应用 patch 到原项目

```bash
smart_box apply --id task-001
```

安全要求：

1. 应用前必须检查原项目当前 git 状态；
2. 如果原项目有未提交改动，默认拒绝；
3. 除非用户显式传入 `--force`；
4. 应用 patch 前生成备份 patch；
5. 应用后输出原项目 diff。

建议：

```bash
smart_box apply --id task-001 --dry-run
smart_box apply --id task-001
smart_box apply --id task-001 --force
```

---

### 8.11 丢弃 box

```bash
smart_box discard --id task-001
```

行为：

1. 删除 box 目录；
2. 如果是 git-worktree mode，需要正确移除 worktree；
3. 记录 discard 操作。

---

## 9. 两种模式的实现要求

### 9.1 copy mode

命令：

```bash
smart_box create --source . --id task-001 --mode copy
```

行为：

1. 复制 source 项目到 `.smart_box/boxes/task-001/workspace`；
2. 排除 `.smart_box` 自身；
3. 排除常见大目录，例如：

   * `.git`
   * `node_modules`
   * `vendor/bundle`
   * `.bundle`
   * `tmp`
   * `log`
4. 在 workspace 内初始化 git；
5. 创建 initial checkpoint。

优点：

* 简单；
* 不要求原项目必须是 git 仓库；
* 适合 MVP。

缺点：

* 大项目复制成本高；
* 对依赖目录处理需要小心。

---

### 9.2 git-worktree mode

命令：

```bash
smart_box create --source . --id task-001 --mode git-worktree
```

前提：

* source 必须是 git 仓库；
* source 当前状态最好 clean；
* 如果 source dirty，需要提示用户或拒绝。

行为：

1. 创建新分支，例如：
   `smart-box/task-001`
2. 使用 `git worktree add` 创建工作目录；
3. 在 worktree 中执行所有命令；
4. checkpoint 可直接用 git commit；
5. export patch 使用 git diff 或 format-patch。

优点：

* 适合真实代码项目；
* 更快；
* 与 git 工作流天然兼容。

缺点：

* 依赖 git；
* 对 dirty working tree 要严格处理。

---

## 10. Ruby API 设计

除了 CLI，还应暴露 Ruby API。

建议：

```ruby
require "smart_box"

box = SmartBox::Box.create(
  source: ".",
  id: "task-001",
  mode: :copy,
  name: "fix bundler conflict"
)

result = box.run("bundle install")

box.checkpoint("after bundle install")

puts box.diff

box.rollback("cp-001")

box.export_patch("fix.patch")

box.apply(dry_run: true)
```

### 10.1 Box 类

需要实现：

```ruby
module SmartBox
  class Box
    attr_reader :id, :source_path, :workspace_path, :mode, :metadata

    def self.create(source:, id:, mode:, name: nil)
    end

    def self.load(source:, id:)
    end

    def run(command, env: {}, timeout: nil)
    end

    def status
    end

    def checkpoint(name)
    end

    def checkpoints
    end

    def rollback(checkpoint_id)
    end

    def diff(from: nil, to: nil)
    end

    def export_patch(output:)
    end

    def apply(dry_run: false, force: false)
    end

    def discard
    end
  end
end
```

### 10.2 CommandResult

```ruby
module SmartBox
  class CommandResult
    attr_reader :command, :cwd, :stdout, :stderr, :exit_code, :started_at, :ended_at

    def success?
      exit_code == 0
    end
  end
end
```

---

## 11. 日志设计

### 11.1 人类可读日志

路径：

```text
.smart_box/boxes/<id>/logs/commands.log
```

示例：

```text
[2026-06-05 10:40:00] RUN bundle install
cwd: workspace
exit_code: 1

STDOUT:
Resolving dependencies...

STDERR:
Bundler could not find compatible versions...
```

### 11.2 机器可读日志

路径：

```text
.smart_box/boxes/<id>/logs/commands.jsonl
```

每行一个 JSON。

示例：

```json
{"time":"2026-06-05T10:40:00+08:00","box_id":"task-001","event":"command_started","command":"bundle install"}
{"time":"2026-06-05T10:40:03+08:00","box_id":"task-001","event":"command_finished","command":"bundle install","exit_code":1}
```

---

## 12. 安全策略

MVP 中不做强隔离，但必须实现基础安全策略。

### 12.1 默认禁止

在 `run` 中默认拒绝明显危险命令：

```text
rm -rf /
mkfs
dd if=
shutdown
reboot
sudo
chmod -R 777 /
chown -R
```

可以先做简单字符串匹配，不需要复杂 AST。

### 12.2 可显式允许

允许用户传入：

```bash
smart_box run --id task-001 --allow-dangerous -- sudo apt install xxx
```

但默认不要允许。

### 12.3 工作目录限制

命令必须在 box workspace 内执行。

如果用户指定 cwd，必须检查 cwd 是否仍在 workspace 内。

---

## 13. 错误处理

定义清晰异常类型：

```ruby
module SmartBox
  class Error < StandardError; end
  class BoxAlreadyExistsError < Error; end
  class BoxNotFoundError < Error; end
  class InvalidModeError < Error; end
  class DirtySourceError < Error; end
  class CheckpointNotFoundError < Error; end
  class DangerousCommandError < Error; end
  class PatchApplyError < Error; end
end
```

CLI 中应把异常转成清晰错误信息。

示例：

```text
Error: Source project has uncommitted changes.
Use --allow-dirty if you really want to create a box from current state.
```

---

## 14. 验收标准

### 14.1 copy mode 验收

准备一个测试项目：

```text
demo/
  README.md
  hello.rb
```

执行：

```bash
smart_box create --source demo --id task-001 --mode copy
smart_box run --id task-001 -- ruby hello.rb
smart_box run --id task-001 -- ruby -e 'File.write("new.txt", "hello")'
smart_box checkpoint --id task-001 --name "add new file"
smart_box diff --id task-001
smart_box export-patch --id task-001 --output fix.patch
smart_box rollback --id task-001 --checkpoint cp-001
smart_box status --id task-001
```

必须满足：

* 原项目没有被修改；
* box workspace 中可以执行命令；
* diff 能显示新增文件；
* rollback 后新增文件消失；
* patch 文件可生成；
* 日志完整记录。

### 14.2 git-worktree mode 验收

准备一个 git 项目。

执行：

```bash
smart_box create --source . --id task-002 --mode git-worktree
smart_box run --id task-002 -- ruby -e 'File.write("box.txt", "from box")'
smart_box checkpoint --id task-002 --name "add box file"
smart_box diff --id task-002
smart_box export-patch --id task-002 --output box.patch
smart_box apply --id task-002 --dry-run
smart_box discard --id task-002
```

必须满足：

* 创建独立 git worktree；
* 原项目目录不直接改变；
* checkpoint 成功；
* patch 可导出；
* discard 后 worktree 被正确移除。

---

## 15. README 首版应包含

README 至少包含：

```text
# smart_box

## What is smart_box?

## Why smart_box?

## Installation

## Quick Start

## Concepts
- Source Project
- Box
- Checkpoint
- Diff
- Patch

## CLI Usage

## Ruby API Usage

## Modes
- copy
- git-worktree

## Safety Notes

## Roadmap
```

---

## 16. 开发顺序建议

请按以下顺序实现：

### Step 1：项目骨架

* 创建 gem 结构；
* 添加 `bin/smart_box`；
* 添加 `SmartBox::VERSION`；
* 能运行 `smart_box --version`。

### Step 2：Box create / load

* 实现 `SmartBox::Box.create`；
* 实现 `SmartBox::Box.load`；
* 写入 `metadata.yml`；
* 支持 copy mode。

### Step 3：run command

* 实现 `box.run(command)`；
* 捕获 stdout / stderr / exit_code；
* 写 commands.log；
* 写 commands.jsonl。

### Step 4：checkpoint / rollback

* 在 workspace 初始化 git；
* checkpoint = git commit；
* rollback = git reset --hard。

### Step 5：diff / export patch

* 实现 `box.diff`；
* 实现 `box.export_patch`。

### Step 6：apply / discard

* 实现 dry-run apply；
* 实现真实 apply；
* 实现 discard。

### Step 7：git-worktree mode

* 检查 source 是否 git 仓库；
* 创建 worktree；
* 移除 worktree；
* 接入已有 checkpoint / diff / patch 机制。

---

## 17. 非目标

首版不要做以下内容：

* 不要做完整 Agent；
* 不要接入 LLM；
* 不要做 TUI；
* 不要做 Web UI；
* 不要做多 Agent 调度；
* 不要做 Docker 沙箱；
* 不要做复杂权限系统；
* 不要做插件市场。

`smart_box` 的首要目标是稳定、简单、可测试。

---

## 18. 最小成功定义

当以下场景可以稳定完成时，MVP 即为成功：

> Coding Agent 在一个真实 Ruby 项目中创建 smart_box，在 box 中执行 `bundle install`，修改 Gemfile，创建 checkpoint，查看 diff，导出 patch，回滚到初始状态，并且原项目目录始终没有被直接污染。

---

## 19. 未来扩展方向

MVP 完成后再考虑：

1. Docker / DevContainer mode；
2. command policy 配置；
3. network policy；
4. resource limits；
5. 并发 box；
6. box branch / alternative solution；
7. 与 SmartExpert TUI 集成；
8. 与 SmartCoder 工作流集成；
9. MCP tool wrapper；
10. JSON-RPC server 模式。

---

## 20. Coding Agent 执行要求

请严格按照以下原则编码：

1. 每一步都写清楚文件改动；
2. 优先实现可运行的最小版本；
3. 不要提前引入复杂依赖；
4. 每完成一个核心功能，都补充基本测试；
5. 不要直接修改用户真实项目，除非实现 `apply` 且用户显式调用；
6. 所有文件路径都使用绝对路径归一化，避免路径穿越；
7. 所有命令执行都必须限制在 workspace 内；
8. 所有外部命令调用都必须记录日志；
9. CLI 输出要适合人类阅读；
10. Ruby API 要保持清晰、可复用。

本项目的第一目标不是“功能多”，而是“安全、可回退、可验证”。
