# frozen_string_literal: true

require "yaml"
require "time"

module SmartBox
  class Metadata
    attr_reader :path, :data

    def initialize(path)
      @path = path
      @data = {}
    end

    def load!
      if File.exist?(@path)
        @data = YAML.safe_load_file(@path, permitted_classes: [Time]) || {}
      end
      self
    end

    def save!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)
      File.write(@path, YAML.dump(@data))
      self
    end

    # --- Convenience accessors ---

    def id
      @data["id"]
    end

    def id=(val)
      @data["id"] = val
    end

    def name
      @data["name"]
    end

    def name=(val)
      @data["name"] = val
    end

    def mode
      @data["mode"]
    end

    def mode=(val)
      @data["mode"] = val
    end

    def source_path
      @data["source_path"]
    end

    def source_path=(val)
      @data["source_path"] = val
    end

    def workspace_path
      @data["workspace_path"]
    end

    def workspace_path=(val)
      @data["workspace_path"] = val
    end

    def status
      @data["status"] || "active"
    end

    def status=(val)
      @data["status"] = val
    end

    def created_at
      @data["created_at"]
    end

    def created_at=(val)
      @data["created_at"] = val
    end

    def updated_at
      @data["updated_at"] || Time.now.utc.iso8601
    end

    def updated_at=(val)
      @data["updated_at"] = val
    end

    def base
      @data["base"] ||= {}
    end

    def base=(val)
      @data["base"] = val
    end

    def checkpoints
      @data["checkpoints"] ||= []
    end

    def stats
      @data["stats"] ||= {}
    end

    def stats=(val)
      @data["stats"] = val
    end

    def add_checkpoint(id:, name:, git_commit:, created_at: Time.now.utc.iso8601)
      checkpoints << {
        "id"         => id,
        "name"       => name,
        "git_commit" => git_commit,
        "created_at" => created_at
      }
    end
  end
end
