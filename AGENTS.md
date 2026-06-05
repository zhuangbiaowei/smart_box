# smart_box

A local reversible sandbox system for Coding Agent task execution.

## Quick Reference

- **Create**: `smart_box create --source . --id task-001 --mode copy`
- **Run**: `smart_box run --id task-001 -- bundle install`
- **Snapshot**: `smart_box checkpoint --id task-001 --name "after change"`
- **Inspect**: `smart_box diff --id task-001`
- **Export**: `smart_box export-patch --id task-001 --output my.patch`
- **Undo**: `smart_box rollback --id task-001 --checkpoint cp-001`
- **Apply**: `smart_box apply --id task-001`
- **Cleanup**: `smart_box discard --id task-001`

See [README.md](README.md) and [docs/design.md](docs/design.md) for full details.
