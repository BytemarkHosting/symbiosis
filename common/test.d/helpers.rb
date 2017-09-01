require 'symbiosis'
require 'fileutils'

# helpers for the rest of the tests in this dir
module TestHelpers

  def make_test_hook(hooks_dir)
    hook = strip_heredoc <<HOOK
  #!/bin/bash

  echo "$1" > #{args_path}
  cat > #{out_path}
HOOK

    FileUtils.mkdir_p hooks_dir

    IO.write Symbiosis.path_in_etc(hooks_dir, 'hook'),
             hook, mode: 'w', perm: 0o755

    HookOutput.new args_path, output_path
  end

  # returned by make_test_hook so you can easily read the args/output back
  class HookOutput
    def initialize(args_path, output_path)
      @args_path = args_path
      @output_path = output_path
    end

    def args
      return @args if @args

      @args = IO.read @args_path

      FileUtils.rm_f @args_path
      @args
    end

    def output
      return @output if @output

      @output = IO.read @output_path

      FileUtils.rm_f @output_path
      @output
    end
  end

  def strip_heredoc
    indent = scan(/^[ \t]*(?=\S)/).min.try(:size) || 0
    String.gsub(/^[ \t]{#{indent}}/, '')
  end
end
