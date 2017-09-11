require 'symbiosis/hooks'
require 'symbiosis/utils'
require 'pathname'

module Symbiosis
  # Manages copying a domain skeleton into a freshly-made domain
  class DomainSkeleton
    attr_reader :skel_dir

    def initialize(skel_dir = Symbiosis.path_in_etc('symbiosis', 'skel.d'))
      @skel_dir = skel_dir
    end

    def params
      Dir.glob(File.join(@skel_dir, '**', '*'))
         .select { |f| File.file?(f) }
    end

    def should_populate?(domain)
      Dir.mkdir domain.config_dir
    rescue Errno::EEXIST
      false
    end

    # after running should_populate? the config directory will have the wrong uid, so set it right
    def ensure_config_owner(domain)
      File.lchown domain.uid, domain.gid, domain.config_dir 
    end

    def path_relative_to_skel(path)
      skel = Pathname.new(@skel_dir)
      pathname = Pathname.new(path)
      pathname.relative_path_from(skel).to_s
    end

    def copy_file!(rel_path, domain)
      verbose "Reading skeleton #{rel_path}"
      src_path = File.join(@skel_dir, rel_path)
      contents = Symbiosis::Utils.safe_open(src_path, File::RDONLY){|fh| fh.read}

      new_path = File.join domain.directory, rel_path
      new_dir = File.dirname new_path

      verbose "Ensuring #{new_dir} exists"
      Symbiosis::Utils.mkdir_p new_dir

      verbose "Writing #{new_path}"
      Symbiosis::Utils.safe_open(new_path, File::WRONLY|File::CREAT, mode: 0644, uid: domain.uid, gid: domain.gid) do |fh|
        fh.truncate(0)
        fh.write(contents)
      end
    end

    def copy!(domain)
      params.each do |path|
        param_name = File.basename path
        copy_file! path_relative_to_skel(path), domain
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
          ensure_config_owner
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

    def verbose(str)
      warn str if $VERBOSE
    end

    # Hooks for DomainSkeleton
    # by default these live in /etc/symbiosis/skel-hooks.d
    class Hooks < Symbiosis::Hooks
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
