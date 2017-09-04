require 'symbiosis/utils'
require 'pathname'

module Symbiosis
  # Manages copying a domain skeleton into a freshly-made domain
  class DomainSkeleton
    attr_reader :skel_dir

    def initialize(skel_dir = Symbiosis.path_in_etc('symbiosis', 'skel'))
      self.skel_dir = skel_dir
    end

    def params
      Dir.glob(File.join(@skel, '**', '*'))
         .select { |f| File.file?(f) }
    end

    def should_populate?(domain)
      !domain.configured?
    end

    # abuse Symbiosis::Utils.get_param and Symbiosis::Utils.set_param
    # as a copy method because they do lots of safety checks for us.
    def copy!(domain)
      skel = Pathname.new(@skel)
      params.each do |path|
        pathname = Pathname.new(path)
        param_rel_path = pathname.relative_path_from(skel).to_s

        param_rel_dir = File.dirname param_rel_path
        param_name = File.basename param_rel_path


        value = Symbiosis::Utils.get_param(param_name, File.join(@skel, param_rel_dir))
        Symbiosis::Utils.mkdir_p File.join(domain.directory, param_rel_dir)
        Symbiosis::Utils.set_param(param_name, value, File.join(domain.directory, param_name))
      end
    end

    def populate!(domain)
      false unless should_populate? domain
      copy!(domain)
      Hooks.run!('domain-populated', [domain])
    end

    # Hooks for DomainSkeleton
    # by default these live in /etc/symbiosis/skel-hooks.d
    class Hooks
      HOOKS_DIR = File.join('symbiosis', 'skel-hooks.d')
      def self.run!(event, domains)
        Symbiosis::DomainSkeleton::Hooks.new.run!(event, domains)
      end

      def initialize(hooks_dir = Symbiosis.path_in_etc(HOOKS_DIR))
        super hooks_dir
      end
    end
  end
end
