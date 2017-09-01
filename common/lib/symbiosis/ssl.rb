require 'symbiosis'
require 'symbiosis/domainhooks'
require 'open3'

module Symbiosis
  # SSL knows about which SSL providers exist and provides SSL helper functions
  class SSL
    PROVIDERS ||= []

    # Hooks for SSL
    class Hooks < Symbiosis::DomainHooks
      HOOKS_DIR = File.join('symbiosis', 'ssl-hooks.d').freeze

      def self.run!
        Symbiosis::SSL::Hooks.new.run!
      end

      def initialize(hooks_dir = Symbiosis.path_in_etc(HOOKS_DIR))
        super hooks_dir
      end
    end
  end
end
