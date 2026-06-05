# frozen_string_literal: true

module SmartBox
  class Error < StandardError; end

  class BoxAlreadyExistsError < Error; end
  class BoxNotFoundError < Error; end
  class InvalidModeError < Error; end
  class DirtySourceError < Error; end
  class CheckpointNotFoundError < Error; end
  class DangerousCommandError < Error; end
  class PatchApplyError < Error; end
end
