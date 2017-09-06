require 'symbiosis/domain_hooks'
require 'symbiosis/utils'
require 'pathname'

module Symbiosis
  # Manages copying a domain skeleton into a freshly-made domain
  class DomainSkeleton
    attr_reader :skel_dir

    def initialize(skel_dir = Symbiosis.path_in_etc('symbiosis', 'skel'))
      @skel_dir = skel_dir
    end

    def params
      Dir.glob(File.join(@skel_dir, '**', '*'))
         .select { |f| File.file?(f) }
    end

    def should_populate?(domain)
      Dir.mkdir File.join(domain.directory, 'config')
    rescue Errno::EEXIST
      false
    end

    def param_rel_dir(path)
      skel = Pathname.new(@skel_dir)
      pathname = Pathname.new(path)
      param_rel_path = pathname.relative_path_from(skel).to_s

      File.dirname(param_rel_path)
    end

    # abuse Symbiosis::Utils.get_param and Symbiosis::Utils.set_param
    # as a copy method because they do lots of safety checks for us.
    def copy!(domain)
      params.each do |path|
        param_name = File.basename path

        old_param_dir = File.join(@skel_dir, param_rel_dir(path))
        new_param_dir = File.join(domain.directory, param_rel_dir(path))

        value = Symbiosis::Utils.get_param(param_name, old_param_dir)

        Symbiosis::Utils.mkdir_p new_param_dir
        Symbiosis::Utils.set_param(param_name, value, new_param_dir)
      end
      true
    end

    # returns an array of key-value pair arrays
    # where the key is the domain name and the
    # value is an error or nil. If nil the copy for that
    # domain was successful.
    def try_copy!(domains)
      domains.map do |domain|
        begin
          warn "Copying skeleton to #{domain.directory}..."
          copy! domain
          warn "Copy completed for #{domain.directory}"
          [domain.name, nil]
        rescue => e
          warn "Error copying to #{domain.directory} - #{e}"
          [domain.name, e]
        end
      end
    end

    def populate!(domains)
      warn "Checking which domains to populate..."
      domains = domains.select { |domain| should_populate? domain }
      warn "Populating [#{domains.join(", ")}]"
      # convert [ [key, value], ... ] from try_copy! to a hash
      Hash[try_copy!(domains)]
    end

    # Hooks for DomainSkeleton
    # by default these live in /etc/symbiosis/skel-hooks.d
    class Hooks < Symbiosis::DomainHooks
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
