require "smart_box"

module SmartBox
  module CLI
    def self.run(argv = ARGV)
      command = argv.first

      case command
      when "--version", "-v"
        puts "smart_box #{SmartBox::VERSION}"
      when "--help", "-h", nil
        print_help
      else
        puts "Unknown command: #{command}"
        print_help
        exit 1
      end
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
