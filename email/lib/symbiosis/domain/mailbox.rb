
require 'symbiosis/domains'
require 'symbiosis/domain'
require 'socket'

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
        @encrypt_password = @domain.should_encrypt_mailbox_passwords?
        @password      = nil
        @local_user    = nil
      end

      #
      # Sets the local_user parameter, which is used for local mailboxes.
      #
      def local_user=(u)
        raise ArgumentError unless u.is_a?(Struct::Passwd)
        @local_user = u
      end

      #
      # Return the local_user (if set).
      #
      def local_user
        @local_user
      end

      #
      # Return the UID for this mailbox
      #
      def uid
        if self.local_user.is_a?(Struct::Passwd)
          self.local_user.uid
        else
          self.domain.uid
        end
      end

      #
      # Return the GID for this mailbox
      #
      def gid
        if self.local_user.is_a?(Struct::Passwd)
          self.local_user.gid
        else
          self.domain.gid
        end
      end

      #
      # Returns the username required for IMAP/POP3/SMTP authentication.
      #
      def username
        [self.local_part, self.domain.name].join("@")
      end

      #
      # If the local_user is set, then this returns ".", otherwise it returns "".
      #
      def dot
        if self.local_user.is_a?(Struct::Passwd)
          "."
        else
          ""
        end
      end

      #
      # Returns the directory for the mailbox
      #
      def directory
        if self.local_user.is_a?(Struct::Passwd)
          @local_user.dir
        else
          File.join(self.domain.directory, self.mailboxes_dir, self.local_part)
        end
      end

      #
      # Returns the location of the Maildir
      #
      def maildir
        File.join(self.directory, "Maildir")
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

        set_param(self.dot + "quota", q, self.directory)

        ans
      end

      #
      # Retuns any quota set.  If nothing has been set for this mailbox, the
      # domain's quota is used.
      #
      def quota
        quota = nil
        param = get_param(self.dot + "quota",self.directory)

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
      # This checks to see if the quota file updated by Dovecot/Exim4 needs to
      # be removed, in case of quota changes.
      #
      def rebuild_maildirsize
        #
        # Make sure the Maildir directory exists -- create it if missing.
        #
        self.domain.create_dir(self.maildir, 0700) unless File.directory?(self.maildir)

        #
        # Create all the subdirectories
        #
        %w(new cur tmp).each do |d|
          sub_dir = File.join(self.maildir, d)
          self.domain.create_dir(sub_dir, 0700) unless File.directory?(sub_dir)
        end

        #
        # Fetch the real quota, and set it to zero if none is set.
        #
        expected_size  = self.quota
        expected_count = 0

        #
        # If no quota has been set, or it is zero, remove the maildirsize file.
        #
        if expected_size.nil? or (0 == expected_size and 0 == expected_count)
          set_param("maildirsize", false, self.maildir)
          return nil
        end

        #
        # Now fetch + parse definition
        #
        real_size  = 0
        real_count = 0
        real_quota_definition = get_param("maildirsize", self.maildir)

        #
        # If no real_quota_definition was found, set it to an empty string.
        #
        real_quota_definition = "" if false == real_quota_definition

        real_quota_definition.split(",").each do |qpart|
          case qpart
            when /^(\d+)S$/
              real_size = $1
            when /^(\d+)C$/
              real_count = $1
            else
              next
          end
        end

        #
        # If things are OK, just return
        #
        return nil if (real_count == expected_count) and (real_size == expected_size)

        #
        # Otherwise rebuild the maildirsize file, unless real matches expectation.
        #
        used_size = 0
        used_count = 0

        %w(new cur).each do |dir|
          Dir.glob(File.join(self.maildir,"**",dir,"*"), File::FNM_DOTMATCH).each do |fn|
            next unless File.file?(fn)
            used_count += 1
            #
            #  ,S=nnnn[:,]
            #
            if fn =~ /,S=(\d+)(?:[:,]|$)/
              used_size += $1.to_i
            else
              begin
                used_size += File.stat(fn).size
              rescue Erro::ENOENT
                # do nothing
              end
            end
          end
        end

        #
        # This is the OFFISHAL way.  See http://www.courier-mta.org/imap/README.maildirquota.html
        #
        # Start with a temporary file, using DJB's unique name generator. http://cr.yp.to/proto/maildir.html 
        # 
        tv = Time.now
        tmpfile = File.join(self.maildir, "tmp", [tv.tv_sec, "M#{tv.tv_usec}P#{Process.pid}", Socket.gethostname].join("."))

        #
        # Make sure there's a temporary directory available
        #
        self.domain.create_dir(File.dirname(tmpfile), 0700) unless File.exist?(File.dirname(tmpfile))

        begin
          #
          # Now open the temp file, and write
          #
          safe_open(tmpfile, File::WRONLY|File::CREAT, :mode => 0644, :uid => self.uid, :gid => self.gid) do |fh|
            #
            # Truncate the file and write.
            #
            fh.truncate(0)

            #
            # Apparently we should make sure the line is 14 characters long, including newline.
            #
            fh.write "#{expected_size}S,#{expected_count}C".ljust(13) + "\n"
            fh.write "#{used_size} #{used_count}".ljust(13) + "\n"
          end

          #
          # Now rename our file.
          #
          File.rename(tmpfile, File.join(self.maildir, "maildirsize"))

        ensure
          #
          # Make sure we clear up after ourselves.
          #
          File.unlink(tmpfile) if File.exist?(tmpfile)
        end

        return nil
      end

      #
      # Returns the name of the mailbox password file.
      #
      def password_file
        if @local_user
          File.join(self.directory,".password")
        else
          File.join(self.directory,"password")
        end
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
          param = get_param(self.dot + "password", self.directory, :mode => 0600)

          unless param.is_a?(String)
            @password = nil
          else
            @password = param.strip
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
        self.create

        if pw != self.password

          p_dir, p_file = File.split(self.password_file)

          if @encrypt_password 
            set_param(self.dot + "password", self.domain.crypt_password(pw), self.directory, :mode => 0600)
          else
            set_param(self.dot + "password", pw, self.directory, :mode => 0600)
          end
        end

        return (@password = pw)
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
        return domain.check_password(pw, self.password)
      end

    end

    #
    # Return all the mailboxes for this domain. This method is not thread-safe,
    # I don't think.
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

      primary_hostname = Socket.gethostname

      #
      # If this is the primary hostname, then add in more local mailboxes
      #
      if primary_hostname == self.name
        while (user = Etc.getpwent) do
          #
          # Skip is this username is admin
          # 
          next if user.name == "admin"

          #
          # Skip if the it is a system user
          #
          next unless user.uid >= 1000

          #
          # Make sure it is a valid local part
          #
          next unless Mailbox.valid_local_part?(user.name)

          #
          # Make sure $HOME exists.
          #
          next unless File.directory?(user.dir)

          #
          # If we've already got this name, skip.
          #
          next if results.any?{|mailbox| mailbox.local_part == user.name}

          this_mailbox = Mailbox.new(user.name, self)
          this_mailbox.local_user = user
          
          results << this_mailbox
        end

        Etc.endpwent
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

      set_param("mailbox-quota", quota, self.config_dir)

      ans
    end

    #
    # Fetches the default mailbox quota for the domain.  Returns an integer, or
    # nil if no quota was set or the set quota could not be parsed.
    #
    def default_mailbox_quota
      quota = nil
      param = get_param("mailbox-quota",self.config_dir)

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

    #
    # Returns true if this domain has email password encryption enabled.
    #
    def should_encrypt_mailbox_passwords?
      if get_param("mailbox-dont-encrypt-passwords",self.config_dir)
        false
      else
        true
      end
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
