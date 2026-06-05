# frozen_string_literal: true

module SmartBox
  module Modes
    class GitWorktreeMode
      attr_reader :source_path, :workspace_path, :branch_name

      def initialize(source_path:, workspace_path:, box_id:)
        @source_path    = File.expand_path(source_path)
        @workspace_path = File.expand_path(workspace_path)
        @box_id         = box_id
        @branch_name    = "smart-box/#{box_id}"
      end

      # --- entry points ---

      def setup
        validate_source!
        ensure_branch!
        create_worktree!
        init_checkpoint!
      end

      def teardown
        remove_worktree! if worktree_exists?
      end

      private

      def validate_source!
        unless Dir.exist?(@source_path)
          raise SmartBox::Error, "Source directory not found: #{@source_path}"
        end

        unless Dir.exist?(File.join(@source_path, ".git"))
          raise SmartBox::Error, "Source is not a git repository. git-worktree mode requires a git repo."
        end

        # Check if source is clean
        unless source_clean?
          raise DirtySourceError,
            "Source project has uncommitted changes.\n" \
            "Commit or stash your changes before creating a git-worktree box, " \
            "or use copy mode instead."
        end
      end

      def source_clean?
        Dir.chdir(@source_path) do
          `git status --porcelain 2>/dev/null`.strip.empty?
        end
      end

      def ensure_branch!
        Dir.chdir(@source_path) do
          branches = `git branch --list #{@branch_name} 2>/dev/null`.strip
          if branches.empty?
            system("git", "branch", @branch_name, out: File::NULL, err: File::NULL)
          end
        end
      end

      def create_worktree!
        Dir.chdir(@source_path) do
          system("git", "worktree", "add", @workspace_path, @branch_name,
                 out: File::NULL, err: File::NULL)
        end

        unless Dir.exist?(@workspace_path)
          raise SmartBox::Error, "Failed to create git worktree at #{@workspace_path}"
        end
      end

      def init_checkpoint!
        Dir.chdir(@workspace_path) do
          system("git", "add", "-A", out: File::NULL, err: File::NULL)
          system("git", "commit", "--allow-empty", "-m", "smart_box initial checkpoint",
                 out: File::NULL, err: File::NULL)
        end
      end

      def remove_worktree!
        Dir.chdir(@source_path) do
          system("git", "worktree", "remove", @workspace_path, "--force",
                 out: File::NULL, err: File::NULL)
          system("git", "branch", "-D", @branch_name,
                 out: File::NULL, err: File::NULL)
        end
      end

      def worktree_exists?
        Dir.chdir(@source_path) do
          worktrees = `git worktree list --porcelain 2>/dev/null`
          worktrees.include?(@workspace_path)
        end
      end
    end
  end
end
