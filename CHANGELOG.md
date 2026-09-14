# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2026-09-14

### Changed

- Point gemspec homepage/source/changelog/bug-tracker URIs at the real
  repository (github.com/zhuangbiaowei/smart_box).
- Ship the MIT `LICENSE` and `CHANGELOG.md` in the gem.

## [0.1.2] - 2026-09-14

### Fixed

- Eliminate process-wide `Dir.chdir` conflicts. All parent-process `Dir.chdir`
  blocks are replaced with subprocess-level `chdir:` options, so Ruby can no
  longer raise `conflicting chdir during another chdir block` when boxes run in
  background threads.
- Enforce command timeouts. When a `timeout` is set, commands now run via
  `Open3.popen3(pgroup: true)` and the whole process group is terminated
  (TERM, grace period, then KILL) on expiry, returning exit code 124.

## [0.1.1] - 2026-09-13

### Fixed

- Use `require_relative` in `cli.rb` to avoid gem conflict warnings.

## [0.1.0] - 2026-09-13

### Added

- Initial MVP: copy and git-worktree modes, command execution with dangerous
  command detection and logging, checkpoints, rollback, diff, export-patch,
  apply, and discard.

[0.1.3]: https://github.com/zhuangbiaowei/smart_box/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/zhuangbiaowei/smart_box/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/zhuangbiaowei/smart_box/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/zhuangbiaowei/smart_box/releases/tag/v0.1.0
