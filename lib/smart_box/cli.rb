# frozen_string_literal: true

require "smart_box"
require "optparse"

module SmartBox
  module CLI
    def self.run(argv = ARGV)
      parse_options(argv)
      command = argv.first

      case command
      when "--version", "-v"
        puts "smart_box #{SmartBox::VERSION}"
      when "--help", "-h", nil
        print_help
      when "create"
        cmd_create(argv)
      when "list"
        cmd_list(argv)
      when "status"
        cmd_status(argv)
      when "run"
        cmd_run(argv)
      when "checkpoint"
        cmd_checkpoint(argv)
      when "checkpoints"
        cmd_checkpoints(argv)
      when "rollback"
        cmd_rollback(argv)
      when "diff"
        cmd_diff(argv)
      when "export-patch"
        cmd_export_patch(argv)
      when "apply"
        cmd_apply(argv)
      when "discard"
        cmd_discard(argv)
      else
        puts "Unknown command: #{command}"
        print_help
        exit 1
      end
    rescue SmartBox::Error => e
      $stderr.puts "Error: #{e.message}"
      exit 2
    end

    # --- Command implementations ---

    def self.cmd_create(argv)
      opts = parse_create(argv)
      source = opts[:source] || "."
      id     = opts[:id]
      mode   = opts[:mode] || "copy"
      name   = opts[:name]

      unless id
        $stderr.puts "Error: --id is required"
        exit 1
      end

      unless %w[copy git-worktree].include?(mode)
        $stderr.puts "Error: --mode must be 'copy' or 'git-worktree'"
        exit 1
      end

      box = SmartBox::Box.create(source: source, id: id, mode: mode, name: name)

      puts "Box created:"
      puts "  id: #{box.id}"
      puts "  mode: #{box.mode}"
      puts "  workspace: #{box.workspace_path}"
      puts "  checkpoint: cp-001 initial"
    end

    def self.cmd_list(argv)
      opts = parse_source(argv)
      source = opts[:source] || "."

      boxes = SmartBox::Box.list(source: source)

      if boxes.empty?
        puts "No boxes found."
        return
      end

      puts "ID          MODE          STATUS    UPDATED_AT"
      boxes.each do |b|
        updated = b["updated_at"]
        updated = updated[0..15] if updated.is_a?(String) && updated.length > 16
        printf "%-10s  %-12s  %-8s  %s\n",
          b["id"], b["mode"], b["status"], updated
      end
    end

    def self.cmd_status(argv)
      opts = parse_box_opts(argv, require_id: true)
      box  = SmartBox::Box.load(source: opts[:source] || ".", id: opts[:id])
      s    = box.status_summary

      puts "Box: #{s['id']}"
      puts "Mode: #{s['mode']}"
      puts "Status: #{s['status']}"
      puts "Workspace: #{s['workspace']}"
      puts

      if s["changed_files"]&.any?
        puts "Changed files:"
        s["changed_files"].each { |f| puts "  #{f}" }
      else
        puts "No changed files."
      end
      puts

      if s["checkpoints"]&.any?
        puts "Checkpoints:"
        s["checkpoints"].each do |cp|
          cp.each { |id, name| puts "  #{id} #{name}" }
        end
      end
    end

    def self.cmd_run(argv)
      argv.shift  # remove "run" subcommand name
      opts = parse_run(argv)
      id = opts[:id]

      unless id
        $stderr.puts "Error: --id is required"
        exit 1
      end

      command = argv.join(" ")
      if command.empty?
        $stderr.puts "Error: command is required (use -- before command args)"
        exit 1
      end

      box = SmartBox::Box.load(source: opts[:source] || ".", id: id)
      result = box.run(command, allow_dangerous: opts[:allow_dangerous])

      $stdout.write(result.stdout)
      $stderr.write(result.stderr) unless result.stderr.empty?
      exit result.exit_code
    end

    def self.cmd_checkpoint(argv)
      puts "checkpoint: not yet implemented"
    end

    def self.cmd_checkpoints(argv)
      puts "checkpoints: not yet implemented"
    end

    def self.cmd_rollback(argv)
      puts "rollback: not yet implemented"
    end

    def self.cmd_diff(argv)
      puts "diff: not yet implemented"
    end

    def self.cmd_export_patch(argv)
      puts "export-patch: not yet implemented"
    end

    def self.cmd_apply(argv)
      puts "apply: not yet implemented"
    end

    def self.cmd_discard(argv)
      puts "discard: not yet implemented"
    end

    # --- Option parsers ---

    def self.parse_create(argv)
      opts = {}
      OptionParser.new do |p|
        p.on("--source PATH")   { |v| opts[:source] = v }
        p.on("--id ID")         { |v| opts[:id] = v }
        p.on("--mode MODE")     { |v| opts[:mode] = v }
        p.on("--name NAME")     { |v| opts[:name] = v }
      end.parse!(argv)
      opts
    end

    def self.parse_source(argv)
      opts = {}
      OptionParser.new do |p|
        p.on("--source PATH") { |v| opts[:source] = v }
      end.parse!(argv)
      opts
    end

    def self.parse_box_opts(argv, require_id: false)
      opts = {}
      OptionParser.new do |p|
        p.on("--source PATH") { |v| opts[:source] = v }
        p.on("--id ID")       { |v| opts[:id] = v }
      end.parse!(argv)

      if require_id && !opts[:id]
        $stderr.puts "Error: --id is required"
        exit 1
      end
      opts
    end

    def self.parse_run(argv)
      opts = {}
      OptionParser.new do |p|
        p.on("--source PATH")           { |v| opts[:source] = v }
        p.on("--id ID")                 { |v| opts[:id] = v }
        p.on("--allow-dangerous")       { |v| opts[:allow_dangerous] = true }
      end.parse!(argv)
      opts
    end

    def self.parse_options(argv)
      # Global options stripped before command dispatch — handled in `run`
    end

    def self.print_help
      puts <<~HELP
        smart_box #{SmartBox::VERSION}

        Usage:
          smart_box <command> [options]

        Commands:
          create            Create a new box
          list              List boxes
          status            Show box status
          run               Run a command in a box
          checkpoint        Create a checkpoint
          checkpoints       List checkpoints
          rollback          Rollback to a checkpoint
          diff              Show diff
          export-patch      Export patch file
          apply             Apply patch to source project
          discard           Discard a box

        Options:
          --version, -v     Show version
          --help, -h        Show this help
      HELP
    end
  end
end