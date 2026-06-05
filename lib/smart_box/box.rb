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

    private

    attr_reader :box_dir, :metadata_path

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
