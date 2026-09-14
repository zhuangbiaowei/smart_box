# frozen_string_literal: true

require_relative "lib/smart_box/version"

Gem::Specification.new do |spec|
  spec.name          = "smart_box"
  spec.version       = SmartBox::VERSION
  spec.authors       = ["SmartBox Team"]
  spec.summary       = "A local reversible sandbox system for agent task execution"
  spec.description   = <<~DESC
    smart_box is a local sandbox system for Coding Agents. It allows agents to
    perform file modifications, command execution, dependency installation,
    experimental fixes, code generation, diff viewing, checkpoint rollback,
    and patch export without directly polluting the real project directory.
  DESC
  spec.license       = "MIT"
  spec.homepage      = "https://github.com/zhuangbiaowei/smart_box"

  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata = {
    "source_code_uri" => "https://github.com/zhuangbiaowei/smart_box",
    "changelog_uri"   => "https://github.com/zhuangbiaowei/smart_box/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/zhuangbiaowei/smart_box/issues"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "bin/*",
    "README.md",
    "LICENSE",
    "CHANGELOG.md"
  ]

  spec.bindir        = "bin"
  spec.executables   = ["smart_box"]
  spec.require_paths = ["lib"]
end
