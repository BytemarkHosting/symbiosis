require 'symbiosis/utils'
require 'pathname'

module Symbiosis
  # Manages copying a domain skeleton into a freshly-made domain
  class DomainSkeleton
    def initialize(skel_dir = Symbiosis.path_in_etc('symbiosis', 'skel'))
      @skel = skel_dir
    end

    def params
      Dir.glob(File.join(@skel, '**', '*'))
         .select { |f| File.file?(f) }
    end

    def should_populate?(domain)
      !domain.configured?
    end

    def run_hooks!(hooks_dir)
      DomainSkeleton::Hooks.run!(hooks_dir)
    end

    # abuse Symbiosis::Utils.get_param and Symbiosis::Utils.set_param
    # as a copy method because they do lots of safety checks for us.
    def copy!(domain)
      skel = Pathname.new(@skel)
      params.each do |path|
        pathname = Pathname.new(path)
        param_name = pathname.relative_path_from(skel).to_s

        value = Symbiosis::Utils.get_param(param_name, @skel)
        Symbiosis::Utils.set_param(param_name, value, domain.directory)
      end
    end

    def populate!(domain)
      false unless should_populate? domain
      copy!(domain)
      run_hooks!(domain)
    end
  end
end
