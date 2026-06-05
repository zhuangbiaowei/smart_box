# frozen_string_literal: true

module SmartBox
  class CommandResult
    attr_reader :command, :cwd, :stdout, :stderr, :exit_code, :started_at, :ended_at

    def initialize(command:, cwd:, stdout:, stderr:, exit_code:, started_at:, ended_at:)
      @command    = command
      @cwd        = cwd
      @stdout     = stdout
      @stderr     = stderr
      @exit_code  = exit_code
      @started_at = started_at
      @ended_at   = ended_at
    end

    def success?
      @exit_code == 0
    end

    def elapsed_ms
      ((@ended_at - @started_at) * 1000).to_i
    end
  end
end
