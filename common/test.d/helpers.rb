require 'symbiosis'
require 'fileutils'

# helpers for the rest of the tests in this dir
module TestHelpers
  def self.make_test_hook(hooks_dir)
    args_path = Symbiosis.path_in_etc('hook.args')
    output_path = Symbiosis.path_in_etc('hook.output')

    hook = strip_heredoc <<HOOK
  #!/bin/bash

  echo "$1" > #{args_path}
  cat > #{output_path}
HOOK

    FileUtils.mkdir_p hooks_dir

    IO.write File.join(hooks_dir, 'hook'),
             hook, mode: 'w', perm: 0o755

    HookOutput.new args_path, output_path
  end

  # returned by make_test_hook so you can easily read the args/output back
  class HookOutput
    def initialize(args_path, output_path)
      @args_path = args_path
      @output_path = output_path
    end

    def hook_ran?
      return @hook_ran unless @hook_ran.nil?

      @hook_ran = File.exist?(@args_path) && File.exist?(@output_path)
    end

    def args
      return @args if @args
      return nil unless hook_ran?

      @args = IO.read @args_path

      FileUtils.rm_f @args_path
      @args
    end

    def output
      return @output if @output
      return nil unless hook_ran?

      @output = IO.read @output_path

      FileUtils.rm_f @output_path
      @output
    end
  end

  def self.strip_heredoc(heredoc)
    space = heredoc.scan(/^[ \t]*(?=\S)/).min
    indent = space ? space.size : 0

    heredoc.gsub(/^[ \t]{#{indent}}/, '')
  end
end
