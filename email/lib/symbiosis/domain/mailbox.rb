
require 'symbiosis/domains'
require 'symbiosis/domain'

module Symbiosis

  class Domain
    
    class Mailbox
  
      include Symbiosis::Utils

      #
      # Check to see if a local part is valid.
      #
      def self.valid_local_part?(lp)
        #
        # This is defined in exim4.conf too.
        #
        lp.is_a?(String) and lp !~ /^(\.|.*[@%!\/|])/
      end

      attr_reader :local_part, :domain, :mailboxes_dir


      #
      # Set up a new mailbox object.
      #
      # This does not actually create it on disc.
      #
      def initialize(local_part, domain, mailboxes_dir="mailboxes")

        raise ArgumentError, "Not a valid local_part" unless Mailbox.valid_local_part?(local_part)
        raise ArgumentError, "Not a Domain" unless domain.is_a?(Domain)

        @local_part    = local_part
        @domain        = domain
        @mailboxes_dir = mailboxes_dir
        @encrypt_password = true
        @password      = nil
      end

      #
      # Returns the username required for IMAP/POP3/SMTP authentication.
      #
      def username
        [self.local_part, self.domain.name].join("@")
      end

      #
      # Returns the directory for the mailbox
      #
      def directory
        File.join(self.domain.directory, self.mailboxes_dir, self.local_part)
      end

      #
      # Creates the mailbox.  Returns self.
      #
      def create
        self.domain.create_dir(self.directory) unless self.exists?
        self
      end 

      #
      # Returns true if the mailbox already exists.
      #
      def exists?
        File.readable?( self.directory )
      end

      #
      # Sets the individual mailbox quota.  Uses Symbiosis::Utils#parse_quota
      # to check the argment.  Returns an interpreted quota, i.e. an integer or
      # nil.  Creates the mailbox if needed.
      #
      def quota=(q)
        self.create
        
        unless q.nil?
          ans = parse_quota(q)
        else
          ans = nil
        end

        set_param("quota", q, self.directory)

        ans
      end

      #
      # Retuns any quota set.  If nothing has been set for this mailbox, the
      # domain's quota is used.
      #
      def quota
        quota = nil
        param = get_param("quota",self.directory)


        unless param.is_a?(String)
          quota = nil
        else
          begin
            quota = parse_quota(param)
         rescue ArgumentError
            quota = nil
          end
        end

        if quota.nil?
          quota = self.domain.default_mailbox_quota
        end

        quota
      end

      #
      # Returns the name of the mailbox password file.
      #
      def password_file
        File.join(self.directory,"password")
      end

      #
      # Returns the mailbox's password, or nil if one has not been set, or the
      # mailbox doesn't exist.
      #
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

      #
      # Sets the password, creating the mailbox if needed.  If the
      # encrypt_password flag is set then the password is encrypted using
      # Symbiosis::Domain#crypt_password
      #
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

      #
      # Sets the encrypt_password flag.  This is set to true by default.
      #
      def encrypt_password=(bool)
        raise ArgumentError, "Must be true or false" unless [true, false].include?(bool)
        @encrypt_password = bool
      end

      #
      # Try to login to a mailbox using a password.
      #
      # An ArgumentError is raised if login fails.
      #
      # Returns true if login succeeds.
      #
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
    def mailboxes(mailboxes_dir = "mailboxes")
      results = []

      mboxes_dir = File.join(self.directory, mailboxes_dir)

      Dir.glob(File.join(mboxes_dir, "*")).each do |entry|
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
      
      if results.length > 0
        mbox_stat = File.lstat(mboxes_dir)

        #
        # Make sure the mailbox directory is not world-read/write/executable
        #
        File.lchmod((mbox_stat.mode & 0770), mboxes_dir) if mbox_stat.writeable?
      end

      results
    end

    #
    # Find a mailbox for this domain, based on its local part.
    #
    def find_mailbox(local_part)
      return nil unless Mailbox.valid_local_part?(local_part)

      mailboxes.find{|mailbox| mailbox.local_part == local_part}
    end

    #
    # Create a new mail box for a local part.
    # 
    def create_mailbox(local_part, mailboxes_dir = "mailboxes")
      mailbox = Mailbox.new(local_part, self, mailboxes_dir)
      mailbox.create
    end

    #
    # Set the default mailbox quota for the domain.  Uses
    # Symbiosis::Utils#parse_quota to check the argment.  Returns an
    # interpreted quota, i.e. an integer or nil.  
    #
    def default_mailbox_quota=(q)
      unless q.nil?
        ans = parse_quota(quota)
      else
        ans = nil
      end

      set_param("default-mailbox-quota", quota, self.config_dir)

      ans
    end

    #
    # Fetches the default mailbox quota for the domain.  Returns an integer, or
    # nil if no quota was set or the set quota could not be parsed.
    #
    def default_mailbox_quota
      quota = nil
      param = get_param("default-mailbox-quota",self.config_dir)

      unless param.is_a?(String)
        quota = nil
      else
        begin
          quota = parse_quota(param)
       rescue ArgumentError
          quota = nil
        end
      end

      quota
    end

  end

  class Domains
   
    #
    # Finds and returns a mailbox based on an email address.
    #  
    def self.find_mailbox(address, prefix="/srv")
      raise ArgumentError, "Address is not a String" unless address.is_a?(String)
      address = address.downcase.split("@")

      domain = address.pop
      local_part = address.join("@")
      
      domain = find(domain, prefix)
      return nil if domain.nil?

      return domain.find_mailbox(local_part)
    end

  end

end
