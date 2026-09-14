# frozen_string_literal: true

require "fileutils"
require "time"
require "open3"
require_relative "errors"
require_relative "metadata"
require_relative "modes/copy_mode"

module SmartBox
  class Box
    attr_reader :id, :source_path, :workspace_path, :mode, :metadata

    SMART_BOX_DIR = ".smart_box"
    BOXES_DIR     = File.join(SMART_BOX_DIR, "boxes")

    def initialize(source_path:, id:, mode:, name: nil)
      @id          = id
      @mode        = mode.to_s
      @source_path = File.expand_path(source_path)
      @name        = name
      @box_dir     = File.join(@source_path, BOXES_DIR, @id)
      @workspace_path = File.join(@box_dir, "workspace")
      @metadata_path  = File.join(@box_dir, "metadata.yml")
      @metadata       = Metadata.new(@metadata_path)
    end

    # --- Class methods ---

    def self.create(source:, id:, mode:, name: nil)
      box = new(source_path: source, id: id, mode: mode, name: name)

      if Dir.exist?(box.send(:box_dir))
        raise BoxAlreadyExistsError, "Box '#{id}' already exists"
      end

      FileUtils.mkdir_p(box.send(:box_dir))
      FileUtils.mkdir_p(File.join(box.send(:box_dir), "logs"))
      FileUtils.mkdir_p(File.join(box.send(:box_dir), "patches"))
      FileUtils.mkdir_p(File.join(box.send(:box_dir), "checkpoints"))

      mode_instance = box.send(:mode_instance)
      mode_instance.setup

      # Capture initial git commit hash
      initial_commit = box.send(:git_latest_commit)

      box.metadata.id             = id
      box.metadata.name           = name
      box.metadata.mode           = mode.to_s
      box.metadata.source_path    = box.source_path
      box.metadata.workspace_path = box.workspace_path
      box.metadata.status         = "active"
      box.metadata.created_at     = Time.now.utc.iso8601
      box.metadata.updated_at     = Time.now.utc.iso8601
      box.metadata.base           = {
        "type" => mode.to_s,
        "source_git_commit" => box.send(:source_git_commit),
        "source_git_branch" => box.send(:source_git_branch)
      }
      box.metadata.add_checkpoint(
        id:         "cp-001",
        name:       "initial",
        git_commit: initial_commit,
        created_at: Time.now.utc.iso8601
      )
      box.metadata.stats = {
        "commands_count"      => 0,
        "changed_files_count" => 0
      }
      box.metadata.save!

      box
    end

    def self.load(source:, id:)
      box = new(source_path: source, id: id, mode: nil)

      unless Dir.exist?(box.send(:box_dir))
        raise BoxNotFoundError, "Box '#{id}' not found"
      end

      box.metadata.load!

      unless box.metadata.id
        raise BoxNotFoundError, "Box '#{id}' metadata is missing 'id' field"
      end

      box
    end

    def self.list(source:)
      boxes_path = File.join(File.expand_path(source), BOXES_DIR)
      return [] unless Dir.exist?(boxes_path)

      Dir.each_child(boxes_path).filter_map do |entry|
        box_path = File.join(boxes_path, entry)
        next unless Dir.exist?(box_path)

        metadata_path = File.join(box_path, "metadata.yml")
        next unless File.exist?(metadata_path)

        meta = YAML.safe_load_file(metadata_path, permitted_classes: [Time])
        next unless meta.is_a?(Hash)

        {
          "id"         => meta["id"] || entry,
          "mode"       => meta["mode"] || "unknown",
          "status"     => meta["status"] || "unknown",
          "updated_at" => meta["updated_at"] || "unknown"
        }
      end
    end

    # --- Instance methods ---

    def status_summary
      {
        "id"            => @id,
        "mode"          => @mode || @metadata.mode,
        "status"        => @metadata.status,
        "workspace"     => @workspace_path,
        "changed_files" => git_status_short,
        "checkpoints"   => @metadata.checkpoints.map { |cp| { cp["id"] => cp["name"] } }
      }
    end

    def git_status_short
      return [] unless Dir.exist?(@workspace_path)

      out, _err, status = Open3.capture3("git", "status", "--porcelain",
                                         chdir: @workspace_path)
      return [] unless status.success?

      out.lines.map(&:chomp).reject(&:empty?)
    end

    def run(command, env: {}, timeout: nil, allow_dangerous: false)
      runner.run(command, env: env, timeout: timeout, allow_dangerous: allow_dangerous).tap do
        # Update metadata stats
        @metadata.load!
        stats = @metadata.stats
        stats["commands_count"] = (stats["commands_count"] || 0) + 1
        @metadata.updated_at = Time.now.utc.iso8601
        @metadata.save!
      end
    end

    def checkpoint(name)
      raise Error, "Workspace does not exist" unless Dir.exist?(@workspace_path)

      system("git", "add", "-A", chdir: @workspace_path, out: File::NULL, err: File::NULL)
      system("git", "commit", "--allow-empty", "-m", name,
             chdir: @workspace_path, out: File::NULL, err: File::NULL)

      commit = git_latest_commit
      cp_id = "cp-#{format('%03d', (@metadata.checkpoints.size + 1))}"

      @metadata.load!
      @metadata.add_checkpoint(
        id:         cp_id,
        name:       name,
        git_commit: commit,
        created_at: Time.now.utc.iso8601
      )
      @metadata.updated_at = Time.now.utc.iso8601
      @metadata.save!

      { id: cp_id, name: name, commit: commit }
    end

    def checkpoints
      @metadata.load!
      @metadata.checkpoints.map do |cp|
        { "id" => cp["id"], "name" => cp["name"] }
      end
    end

    def rollback(checkpoint_id)
      cp = @metadata.checkpoints.detect { |c| c["id"] == checkpoint_id }
      raise CheckpointNotFoundError, "Checkpoint '#{checkpoint_id}' not found" unless cp

      system("git", "reset", "--hard", cp["git_commit"],
             chdir: @workspace_path, out: File::NULL, err: File::NULL)
      system("git", "clean", "-fd",
             chdir: @workspace_path, out: File::NULL, err: File::NULL)

      @metadata.load!
      @metadata.updated_at = Time.now.utc.iso8601
      @metadata.save!

      { box_id: @id, checkpoint_id: checkpoint_id }
    end

    def diff(from: nil, to: nil)
      raise Error, "Workspace does not exist" unless Dir.exist?(@workspace_path)

      system("git", "add", "-A", chdir: @workspace_path, out: File::NULL, err: File::NULL)

      from_commit = if from
                      resolve_checkpoint_commit(from)
                    else
                      init = @metadata.checkpoints.first
                      init ? init["git_commit"] : "HEAD~1"
                    end

      to_commit = to ? resolve_checkpoint_commit(to) : nil

      if to_commit
        out, _err, _st = Open3.capture3("git", "diff", from_commit, to_commit,
                                        chdir: @workspace_path)
      else
        out, _err, _st = Open3.capture3("git", "diff", "--cached", from_commit,
                                        chdir: @workspace_path)
      end
      out.to_s
    end

    def export_patch(output:, from: nil, to: nil)
      output_path = if output.start_with?("/")
                      output
                    else
                      File.join(Dir.pwd, output)
                    end

      patch_content = diff(from: from, to: to)
      File.write(output_path, patch_content)

      { output: output_path, size: patch_content.bytesize }
    end

    def apply(dry_run: false, force: false)
      raise Error, "Workspace does not exist" unless Dir.exist?(@workspace_path)

      patch_content = diff(from: @metadata.checkpoints.first&.dig("git_commit"))

      if dry_run
        return { dry_run: true, patch_size: patch_content.bytesize }
      end

      # Check if source is a git repo and if it's clean
      if Dir.exist?(File.join(@source_path, ".git"))
        unless force
          check_source_clean!
        end

        # Create backup patch of current source state
        backup_patch_path = File.join(@box_dir, "patches", "backup.patch")
        FileUtils.mkdir_p(File.join(@box_dir, "patches"))

        backup, _err, _st = Open3.capture3("git", "diff", chdir: @source_path)
        File.write(backup_patch_path, backup) unless backup.empty?

        # Apply the patch
        _apply_out, _apply_err, status =
          Open3.capture3("git", "apply", "-v",
                         stdin_data: patch_content, chdir: @source_path)

        unless status.success?
          raise PatchApplyError, "Failed to apply patch. The source project may have conflicts."
        end

        # Show what changed
        result_diff, _err2, _st2 = Open3.capture3("git", "diff", chdir: @source_path)
        result_diff
      else
        # Non-git source: apply patch with patch command
        backup_patch_path = File.join(@box_dir, "patches", "backup.diff")
        FileUtils.mkdir_p(File.join(@box_dir, "patches"))
        File.write(backup_patch_path, "backup not available for non-git source")

        Open3.capture3("patch", "-p1", "-N", "-r", "/dev/null",
                       stdin_data: patch_content, chdir: @source_path)

        "Patch applied to non-git source at #{@source_path}"
      end
    end

    def discard
      raise Error, "Box directory does not exist" unless Dir.exist?(@box_dir)

      # For git-worktree mode, remove the worktree first
      if %w[git-worktree git_worktree].include?(@metadata.mode)
        mode_instance.teardown
      end

      FileUtils.rm_rf(@box_dir)
      @metadata.status = "discarded"
      { id: @id, status: "discarded" }
    end

    def source_clean?
      return true unless Dir.exist?(File.join(@source_path, ".git"))

      out, _err, _st = Open3.capture3("git", "status", "--porcelain",
                                      chdir: @source_path)
      out.strip.empty?
    end

    private

    attr_reader :box_dir, :metadata_path

    def runner
      @runner ||= Runner.new(
        box_id:         @id,
        workspace_path: @workspace_path,
        logs_dir:       File.join(@box_dir, "logs")
      )
    end

    def mode_instance
      current_mode = @mode.to_s.empty? ? @metadata.mode.to_s : @mode.to_s

      case current_mode
      when "copy"
        Modes::CopyMode.new(
          source_path:    @source_path,
          workspace_path: @workspace_path
        )
      when "git-worktree", "git_worktree"
        Modes::GitWorktreeMode.new(
          source_path: @source_path, workspace_path: @workspace_path, box_id: @id
        )
      else
        raise InvalidModeError, "Unknown mode: #{current_mode}"
      end
    end

    def git_latest_commit
      # In git-worktree mode the workspace's `.git` is a FILE (a gitdir
      # pointer), not a directory — so Dir.exist? is false and this would
      # wrongly return "none". File.exist? is true for both files and dirs.
      return "none" unless File.exist?(File.join(@workspace_path, ".git"))

      out, _err, _st = Open3.capture3("git", "rev-parse", "HEAD",
                                      chdir: @workspace_path)
      out.strip
    end

    def source_git_commit
      git_dir = File.join(@source_path, ".git")
      return "none" unless Dir.exist?(git_dir)

      out, _err, _st = Open3.capture3("git", "rev-parse", "HEAD",
                                      chdir: @source_path)
      out.strip
    end

    def source_git_branch
      git_dir = File.join(@source_path, ".git")
      return "none" unless Dir.exist?(git_dir)

      out, _err, _st = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD",
                                      chdir: @source_path)
      out.strip
    end

    def resolve_checkpoint_commit(checkpoint_id)
      cp = @metadata.checkpoints.detect { |c| c["id"] == checkpoint_id }
      if cp
        cp["git_commit"]
      else
        checkpoint_id
      end
    end

    def check_source_clean!
      unless source_clean?
        raise DirtySourceError,
          "Source project has uncommitted changes.\n" \
          "Use --force to apply anyway."
      end
    end
  end
end