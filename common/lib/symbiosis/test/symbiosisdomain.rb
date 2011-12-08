#
#  Ruby class for creating a new domain
#

require 'symbiosis/test'

  module Symbiosis
    module Test
      class SymbiosisDomain
  
        attr_accessor :user, :group
        attr_reader :name

        #
        # Constructor.
        #
        def initialize( name = nil )
          if ( name.nil? )
            @name = Symbiosis::Test.random_string(10)+".test"
          else
            @name = name
          end
          @user  = "admin"
          @group = "admin"
        end

        #
        # Create the /srv/ directory if we're supposed to.
        #
        def create
          create_dir(self.directory) unless self.exists?
        end

        #
        # Destroy if necessary
        #
        def destroy 
          FileUtils.rm_rf(self.directory) if self.exists?
        end

        def directory
          File.join("", "srv", @name)
        end

        #
        # Does the domain name exist locally?
        #
        def exists?
          File.directory? self.directory
        end

        #
        # Allow arbitrary settings in /config to be retrieved
        #
        def get_param(setting, config_dir = "config")
          config_dir = File.join(self.directory, config_dir) unless config_dir[0] == "/"

          Symbiosis::Test.get_param(setting, config_dir)
        end

        #
        # allow setting to be set..
        #
        def set_param(setting, value=nil, config_dir="config")
          config_dir = File.join(self.directory, config_dir) unless config_dir[0] == "/"
          
          create_dir(config_dir) unless File.exists?(config_dir)

          Symbiosis::Test.set_param(setting, value, config_dir)
        end

        def create_dir(d)
          return if File.directory?(d)
          
          Symbiosis::Test.mkdir(d, :mode => 0755, :user => @user, :group => @group)
        end

      end
    end
  end


