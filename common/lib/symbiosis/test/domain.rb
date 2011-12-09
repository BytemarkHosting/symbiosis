#
#  Ruby class for creating a new domain
#

require 'symbiosis/utils'

module Symbiosis
  module Test
    class Domain

      include Symbiosis::Utils

      attr_accessor :user, :group
      attr_reader :name

      #
      # Constructor.
      #
      def initialize( name = nil )
        if ( name.nil? )
          @name = random_string(10)+".test"
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

    end
  end
end


