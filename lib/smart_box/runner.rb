# frozen_string_literal: true

require "open3"
require "json"
require "time"
require "shellwords"
require "fileutils"
require_relative "command_result"
require_relative "errors"

module SmartBox
  class Runner
    # Simple dangerous command patterns (string matching per design spec §12.1)
    DANGEROUS_PATTERNS = [
      /\brm\s+-rf\s+\//,
      /\bmkfs\b/,
      /\bdd\s+if=/,
      /\bshutdown\b/,
      /\breboot\b/,
      /\bsudo\b/,
      /\bchmod\s+-R\s+777\s+\//,
      /\bchown\s+-R\b/
    ].freeze

    # Exit code used when a command exceeds its timeout (GNU timeout convention).
    TIMEOUT_EXIT_CODE = 124
    # Grace period in seconds between TERM and KILL when terminating a process group.
    KILL_GRACE_SECONDS = 2

    attr_reader :box_id, :workspace_path, :logs_dir

    def initialize(box_id:, workspace_path:, logs_dir:)
      @box_id         = box_id
      @workspace_path = File.expand_path(workspace_path)
      @logs_dir       = File.expand_path(logs_dir)
      @command_index  = 0
    end

    # --- main entry point ---

    def run(command, env: {}, timeout: nil, allow_dangerous: false)
      unless allow_dangerous
        check_dangerous!(command)
      end

      started_at = Time.now
      @command_index += 1
      idx = @command_index

      result = execute_command(command, env, timeout, started_at, idx)
      write_logs(command, result, idx)

      result
    end

    private

    def check_dangerous!(command)
      DANGEROUS_PATTERNS.each do |pattern|
        if command.match?(pattern)
          raise DangerousCommandError,
            "Dangerous command detected: #{command.inspect}\n" \
            "Use --allow-dangerous to bypass this check."
        end
      end
    end

    def execute_command(command, env, timeout, started_at, idx)
      stdout_path = File.join(@logs_dir, "#{format('%04d', idx)}.stdout.log")
      stderr_path = File.join(@logs_dir, "#{format('%04d', idx)}.stderr.log")

      FileUtils.mkdir_p(@logs_dir)

      stdout = ""
      stderr = ""
      exit_code = nil

      args = Shellwords.split(command)
      # Never switch the parent process directory: all execution is confined to
      # the workspace via Open3's `chdir:` option. This avoids Ruby's
      # process-wide `conflicting chdir during another chdir block` error when
      # boxes run in background threads alongside other threads in the process.
      if timeout && timeout.to_f > 0
        stdout, stderr, exit_code = execute_with_timeout(args, env, timeout.to_f)
      else
        begin
          if env && !env.empty?
            stdout, stderr, status = Open3.capture3(env, *args, chdir: @workspace_path)
          else
            stdout, stderr, status = Open3.capture3(*args, chdir: @workspace_path)
          end
          exit_code = status.exitstatus
        rescue Errno::ENOENT => e
          stderr = "Command not found: #{e.message}"
          exit_code = 127
        end
      end

      ended_at = Time.now

      File.write(stdout_path, stdout)
      File.write(stderr_path, stderr)

      CommandResult.new(
        command:    command,
        cwd:        @workspace_path,
        stdout:     stdout,
        stderr:     stderr,
        exit_code:  exit_code,
        started_at: started_at,
        ended_at:   ended_at
      )
    end

    # Runs a command with a hard timeout by spawning it in its own process group
    # (pgroup: true) and killing the whole group on timeout. This kills child
    # processes too (e.g. find/rsync), unlike Ruby's Timeout.timeout.
    def execute_with_timeout(args, env, timeout_s)
      popen_args = env && !env.empty? ? [env, *args] : args
      Open3.popen3(*popen_args, chdir: @workspace_path, pgroup: true) do |stdin, out, err, wait_thr|
        stdin.close

        # Drain stdout/stderr concurrently to avoid pipe buffer deadlocks.
        out_reader = Thread.new { out.read }
        err_reader = Thread.new { err.read }

        waiter = Thread.new { wait_thr.join }
        timed_out = false
        unless waiter.join(timeout_s)
          timed_out = true
          kill_process_group!(wait_thr)
        end
        waiter.kill if waiter.alive?

        stdout = out_reader.value
        stderr = err_reader.value
        exit_code = timed_out ? TIMEOUT_EXIT_CODE : wait_thr.value.exitstatus

        if timed_out
          marker = "[timeout] command exceeded #{format('%g', timeout_s)}s and was killed (exit #{TIMEOUT_EXIT_CODE})"
          stderr = stderr.to_s.empty? ? marker : "#{stderr.rstrip}\n#{marker}"
        end

        [stdout, stderr, exit_code]
      end
    rescue Errno::ENOENT => e
      ["", "Command not found: #{e.message}", 127]
    end

    # Sends TERM to the whole process group, waits a grace period, then KILL.
    def kill_process_group!(wait_thr)
      %w[TERM KILL].each_with_index do |signal, idx|
        break unless wait_thr.alive?

        begin
          Process.kill(signal, -wait_thr.pid)
        rescue Errno::ESRCH, Errno::EPERM
          break # Process group is already gone (or we lack permission).
        end
        wait_thr.join(KILL_GRACE_SECONDS) if idx.zero?
      end
    end

    def write_logs(command, result, idx)
      write_human_log(command, result)
      write_jsonl_log(command, result, idx)
    end

    def write_human_log(command, result)
      log_path = File.join(@logs_dir, "commands.log")
      FileUtils.mkdir_p(@logs_dir)

      entry = <<~ENTRY
        [#{result.started_at.strftime('%Y-%m-%d %H:%M:%S')}] RUN #{command}
        cwd: #{result.cwd}
        exit_code: #{result.exit_code}

        STDOUT:
        #{result.stdout.strip.empty? ? '(empty)' : result.stdout.strip}

        STDERR:
        #{result.stderr.strip.empty? ? '(empty)' : result.stderr.strip}

      ENTRY

      File.open(log_path, "a") { |f| f.write(entry) }
    end

    def write_jsonl_log(command, result, idx)
      log_path = File.join(@logs_dir, "commands.jsonl")
      FileUtils.mkdir_p(@logs_dir)

      entry = {
        "time"         => result.started_at.iso8601,
        "box_id"       => @box_id,
        "event"        => "command_finished",
        "command"      => command,
        "cwd"          => result.cwd,
        "exit_code"    => result.exit_code,
        "elapsed_ms"   => result.elapsed_ms,
        "stdout_path"  => "logs/#{format('%04d', idx)}.stdout.log",
        "stderr_path"  => "logs/#{format('%04d', idx)}.stderr.log"
      }

      File.open(log_path, "a") { |f| f.puts(JSON.generate(entry)) }
    end
  end
end
