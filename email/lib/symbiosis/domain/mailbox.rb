
require 'symbiosis/domains'
require 'symbiosis/domain'

module Symbiosis

  class Domain
    
    class Mailbox
  
      include Symbiosis::Utils

      def self.valid_local_part?(lp)
        #
        # This is defined in exim4.conf too.
        #
        lp.is_a?(String) and lp !~ /^(\.|.*[@%!\/|])/
      end

      attr_reader :local_part, :domain, :mailboxes_dir

      def initialize(local_part, domain, mailboxes_dir="mailboxes")

        raise ArgumentError, "Not a valid local_part" unless Mailbox.valid_local_part?(local_part)
        raise ArgumentError, "Not a Domain" unless domain.is_a?(Domain)

        @local_part    = local_part
        @domain        = domain
        @mailboxes_dir = mailboxes_dir
        @encrypt_password = true
        @password      = nil
      end

      def username
        [self.local_part, self.domain.name].join("@")
      end

      def directory
        File.join(self.domain.directory, self.mailboxes_dir, self.local_part)
      end

      def create
        self.domain.create_dir(self.directory) unless self.exists?
        self
      end 

      def exists?
        File.readable?( self.directory )
      end

      def quota=(quota)
        parse_quota(quota)
        set_param("quota", quota, self.directory)
        quota
      end

      def quota
        quota = nil
        param = get_param("quota",self.directory)

        begin
          quota = param.split.first.strip
          quota = parse_quota(param)
        rescue ArgumentError
          quota = nil
        end

        if quota.nil?
          quota = self.domain.default_mailbox_quota
        end

        quota
      end

      def password
        if self.exists? and @password.nil? 
          #
          # Read the password
          #
          param = get_param("password",self.directory)

          unless param.is_a?(String)
            @password = nil
          else
            @password = param.split.first.strip
          end
        end
        @password
      end

      def password=(pw)
        @password = pw
        self.create

        if @encrypt_password
          set_param("password", self.domain.crypt_password(@password), self.directory)
        else
          set_param("password", @password, self.directory)
        end
    
        return @password
      end

      def encrypt_password=(tf)
        raise ArgumentError, "Must be true or false" unless [true, false].include?(tf)
        @encrypt_password = tf
      end

      def login(pw)
        #
        # Do the password check.
        #
        return ArgumentError, "Bad password" unless domain.check_password(pw, self.password)

        return true
      end

    end

    #
    # return all the mailboxes for this domain
    #
    def mailboxes(mailboxes_dir = "mailboxes" )
      results = []

      Dir.glob(File.join(self.directory, mailboxes_dir, "*")).each do |entry|
        #
        # Only looking for directories
        #
        next unless File.directory?(entry)

        this_mailboxes_dir, local_part = File.split(entry)

        #
        # Don't want directories that are not valid local parts.
        #
        next unless Mailbox.valid_local_part?(local_part)

        results << Mailbox.new(local_part, self, mailboxes_dir)
      end

      results
    end

    def find_mailbox(local_part)
      return nil unless Mailbox.valid_local_part?(local_part)

      mailboxes.find{|mailbox| mailbox.local_part == local_part}
    end

    def create_mailbox(local_part, mailboxes_dir = "mailboxes")
      mailbox = Mailbox.new(local_part, self, mailboxes_dir)
      mailbox.create
    end

      def default_mailbox_quota=(quota)
        parse_quota(quota)
        set_param("default-mailbox-quota", quota, self.directory)
        quota
      end

      def default_mailbox_quota
        quota = nil
        param = get_param("default-mailbox-quota",self.directory)

        begin
          quota = param.split.first.strip
          quota = parse_quota(quota)
        rescue ArgumentError
          quota = nil
        end

        quota
      end

    end

  end
  
  class Domains
    
    def self.find_mailbox(address)
      raise ArgumentError, "Address is not a String" unless address.is_a?(String)
      address = address.downcase.split("@")

      domain = address.pop
      local_part = address.join("@")
      
      domain = find(domain)
      return nil if domain.nil?

      return domain.find_mailbox(local_part)
    end

  end

end
