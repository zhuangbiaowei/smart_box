# frozen_string_literal: true

require "fileutils"
require "time"
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

      Dir.chdir(@workspace_path) do
        out = `git status --porcelain 2>/dev/null`
        return [] unless $?.success?

        out.lines.map(&:chomp).reject(&:empty?)
      end
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

      Dir.chdir(@workspace_path) do
        system("git", "add", "-A", out: File::NULL, err: File::NULL)
        system("git", "commit", "--allow-empty", "-m", name, out: File::NULL, err: File::NULL)
      end

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

      Dir.chdir(@workspace_path) do
        system("git", "reset", "--hard", cp["git_commit"], out: File::NULL, err: File::NULL)
        system("git", "clean", "-fd", out: File::NULL, err: File::NULL)
      end

      @metadata.load!
      @metadata.updated_at = Time.now.utc.iso8601
      @metadata.save!

      { box_id: @id, checkpoint_id: checkpoint_id }
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
      case @mode
      when "copy"
        Modes::CopyMode.new(
          source_path:    @source_path,
          workspace_path: @workspace_path
        )
      else
        raise InvalidModeError, "Unknown mode: #{@mode}"
      end
    end

    def git_latest_commit
      return "none" unless Dir.exist?(File.join(@workspace_path, ".git"))

      Dir.chdir(@workspace_path) do
        `git rev-parse HEAD 2>/dev/null`.strip
      end
    end

    def source_git_commit
      git_dir = File.join(@source_path, ".git")
      return "none" unless Dir.exist?(git_dir)

      Dir.chdir(@source_path) do
        `git rev-parse HEAD 2>/dev/null`.strip
      end
    end

    def source_git_branch
      git_dir = File.join(@source_path, ".git")
      return "none" unless Dir.exist?(git_dir)

      Dir.chdir(@source_path) do
        `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      end
    end
  end
end
