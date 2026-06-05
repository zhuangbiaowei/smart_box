# smart_box

## What is smart_box?

smart_box is a local reversible sandbox system for Coding Agent task execution.

Its core goal: allow Coding Agents (SmartExpert, SmartCoder, etc.) to perform file
modifications, command execution, dependency installation, experimental fixes, code
generation, diff viewing, checkpoint rollback, and patch export — without directly
polluting the real project directory.

## Why smart_box?

When a Coding Agent runs autonomously, it may:

- Modify source files incorrectly
- Install conflicting dependencies
- Remove critical files
- Produce untested patches

smart_box provides a safety net: every operation happens inside an isolated box
first. The user can inspect, verify, and then explicitly apply changes to the
real project.

## Installation

```bash
gem install smart_box
```

Or via Bundler:

```ruby
gem "smart_box"
```

## Quick Start

```bash
# Create a box from current project (copy mode)
smart_box create --source . --id task-001 --mode copy

# Run a command inside the box
smart_box run --id task-001 -- bundle install

# Create a checkpoint
smart_box checkpoint --id task-001 --name "after bundle install"

# View changes
smart_box diff --id task-001

# Export patch
smart_box export-patch --id task-001 --output fix.patch

# Rollback to initial state
smart_box rollback --id task-001 --checkpoint cp-001 --mode copy

# Apply to source project
smart_box apply --id task-001

# Discard the box
smart_box discard --id task-001
```

## Concepts

- **Source Project**: The original project directory. smart_box never modifies it directly.
- **Box**: An isolated execution space for one task or experiment.
- **Checkpoint**: A saved state inside a box, allowing rollback.
- **Diff**: Changes between the box's current state and a reference point.
- **Patch**: A portable changeset exported from a box for manual review and application.

## CLI Usage

```
smart_box <command> [options]
```

| Command       | Description                          |
|---------------|--------------------------------------|
| create        | Create a new box                     |
| list          | List all boxes                       |
| status        | Show box status                      |
| run           | Execute a command inside a box       |
| checkpoint    | Create a checkpoint                  |
| checkpoints   | List checkpoints in a box            |
| rollback      | Rollback to a checkpoint             |
| diff          | Show diff against checkpoint         |
| export-patch  | Export patch to a file               |
| apply         | Apply box changes to source project  |
| discard       | Discard a box and its workspace      |

## Ruby API Usage

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

## Modes

### copy mode

Copies the source project (excluding `.git`, `node_modules`, etc.) into an
isolated workspace. Simple and works even if the source is not a git repository.

### git-worktree mode

Uses `git worktree add` to create an isolated working directory. Faster for
large projects and natively compatible with git workflows.

## Safety Notes

- Dangerous commands (`rm -rf /`, `sudo`, etc.) are blocked by default.
- All commands are restricted to the box workspace.
- The source project is never modified without explicit `apply`.
- All paths use absolute normalization to prevent path traversal.

## Roadmap

- [x] copy mode
- [x] git-worktree mode
- [ ] Docker / DevContainer mode
- [ ] Command policy configuration
- [ ] Network policy
- [ ] Resource limits
- [ ] Concurrent boxes
- [ ] SmartExpert TUI integration
- [ ] SmartCoder workflow integration
- [ ] MCP tool wrapper
- [ ] JSON-RPC server mode
