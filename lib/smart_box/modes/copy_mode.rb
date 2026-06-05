# frozen_string_literal: true

require "fileutils"
require "time"

module SmartBox
  module Modes
    # copy mode: copies the source project into an isolated workspace directory,
    # then initializes a git repo inside the workspace for checkpoint support.
    class CopyMode
      # Directories and files to exclude when copying the source project
      COPY_EXCLUDES = %w[
        .git
        .smart_box
        node_modules
        vendor/bundle
        .bundle
        tmp
        log
      ].freeze

      EXCLUDE_DIRS = %w[
        .git
        .smart_box
        node_modules
        tmp
        log
      ].freeze

      attr_reader :source_path, :workspace_path

      def initialize(source_path:, workspace_path:)
        @source_path    = File.expand_path(source_path)
        @workspace_path = File.expand_path(workspace_path)
      end

      # --- entry point ---

      def setup
        validate_source!
        create_workspace!
        copy_source!
        init_git!
      end

      def teardown
        FileUtils.rm_rf(@workspace_path) if Dir.exist?(@workspace_path)
      end

      private

      def validate_source!
        unless Dir.exist?(@source_path)
          raise SmartBox::Error, "Source directory not found: #{@source_path}"
        end

        # For copy mode we allow non-git sources, no extra check needed.
      end

      def create_workspace!
        FileUtils.mkdir_p(@workspace_path)
      end

      def copy_source!
        # Use FileUtils.cp_r with a filter to skip excluded directories.
        # Walk through each entry in the source directory
        Dir.each_child(@source_path) do |entry|
          # Skip excluded dirs/files at the top level
          next if EXCLUDE_DIRS.include?(entry)

          # Skip vendor/bundle — it's a nested pattern; handle at top-level
          # since we only walk one level deep via each_child
          next if entry == "vendor"

          src  = File.join(@source_path, entry)
          dest = File.join(@workspace_path, entry)

          if File.directory?(src)
            # vendor directory: copy but skip vendor/bundle
            if entry == "vendor"
              FileUtils.mkdir_p(dest)
              Dir.each_child(src) do |sub|
                next if sub == "bundle"
                FileUtils.cp_r(File.join(src, sub), File.join(dest, sub))
              end
            else
              FileUtils.cp_r(src, dest)
            end
          else
            FileUtils.cp_r(src, dest)
          end
        end
      end

      def init_git!
        Dir.chdir(@workspace_path) do
          system("git", "init", out: File::NULL, err: File::NULL)
          system("git", "config", "user.email", "smart_box@localhost", out: File::NULL, err: File::NULL)
          system("git", "config", "user.name", "smart_box", out: File::NULL, err: File::NULL)
          system("git", "add", "-A", out: File::NULL, err: File::NULL)
          system("git", "commit", "-m", "smart_box initial checkpoint", out: File::NULL, err: File::NULL)
        end
      end
    end
  end
end
