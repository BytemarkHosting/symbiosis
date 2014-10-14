require 'symbiosis/domains'
require 'symbiosis/utils'
require 'eventmachine'
require 'pp'

module Symbiosis
class ApacheLogger < EventMachine::Connection

  class DomainCache
    def initialize(prefix, cache_time=10, clock=nil)
      @prefix = prefix
      @cache_time = cache_time
      @cache = {}
      @clock ||= Proc.new { Time.now }
    end

    def [](k)
      unless @cache[k] && @cache[k].last + @cache_time < @clock.call
        @cache[k] = [ Symbiosis::Domains.find(k, @prefix), @clock.call ]
      end
      @cache[k].first
    end
  end

  def initialize(opts = {})
    #
    # This is cache of domain names to Symbiosis::Domain objects
    #
    @domain_objects ||= DomainCache.new(self.prefix)
    @sync_io            = false
    @max_filehandles    = 50
    @log_filename       = "access.log"
    @default_filehandle = nil
    @default_filename   = "/var/log/apache2/zz-mass-hosting.log"
    @sync_io  = false
    @uid      = nil
    @gid      = nil
    @prefix   = "/srv"
    @filehandles = []

    opts.each do |meth, value|
      meth = (meth.to_s + "=").to_sym
      if self.respond_to?(meth)
        self.__send__(meth, value)
      else
        raise ArgumentError, "Unrecognised parameter #{meth.to_s}"
      end
    end

    super
  end

  #
  # Return the domain prefix
  #
  def prefix
    @prefix ||= "/srv"
  end

  #
  # Set the Symbiosis::Domain prefix
  #
  def prefix=(p)
    @prefix = p
  end

  def default_filename ; @default_filename ; end
  def default_filename=(d) ; @default_filename=d ; end

  #
  # Return our array of filehandles
  #
  def filehandles
    @filehandles
  end

  #
  # Return the log filename
  #
  def log_filename
    @log_filename
  end

  #
  # Set the default log filename (access.log by default)
  #
  def log_filename=(l)
    #
    # Should do some checking here
    #
    @log_filename = l.to_s
  end

  #
  # Return the maximum number of filehandles we can have open at any time.  If
  # this maximum is exceeded the least-used filehandle is closed.
  #
  def max_filehandles
    @max_filehandles
  end

  #
  # Set the maximum number of filehandles we can have open at any one time.
  # Defaults to 50.
  #
  def max_filehandles=(n)
    @max_filehandles = n.to_i
  end

  #
  # Open logs synchronously
  #
  def sync_io
    (@sync_io === true) || false
  end

  def sync_io=(tf)
    @sync_io = (tf === true)
  end

  #
  # Set the default gid
  #
  def gid=(g) ; @gid = g end
  def gid; @gid ; end

  #
  # Set the default uid
  #
  def uid=(u) ; @uid = u ; end
  def uid ; @uid ; end
  
  # 
  # Opens a log file, returning a filehandle, or nil if it wasn't able to.  It
  # also tried to create any parent directories.
  #
  def open_log(log, opts={})
    begin
      #
      # Set a default uid/gid.
      #
      opts = {:uid => self.uid, :gid => self.gid}.merge(opts)

      #
      # Set up a couple of things before we open the file.  This will make
      # sure the ownerships are correct.
      #
      if opts[:domain] && (File.exists?(opts[:domain].directory) ||
        opts[:domain].directory.split('/').zip(log.split('/')).any? { |a,b|
          a != b }
        )
        begin
          parent_dir = File.dirname(log)
          warn "#{$0}: Creating directory #{parent_dir}" if $VERBOSE
          Symbiosis::Utils.mkdir_p(parent_dir, :uid => (opts[:uid] || self.uid), :gid => (opts[:gid] || self.gid) , :mode => 0755)
        rescue Errno::EEXIST
          # ignore
        end
      else
        # Don't recreate removed domains.
        log = nil
      end
  
      warn "#{$0}: Opening log file #{log}" if $VERBOSE
      filehandle = log.nil? ? File.open('/dev/null', 'a+') : Symbiosis::Utils.safe_open(log, "a+", :mode => 0644, :uid => opts[:uid], :gid => opts[:gid] )
      filehandle.sync = opts[:sync]
  
    rescue StandardError => err
      filehandle = nil
      warn "#{$0}: Caught #{err}" if $VERBOSE
    end
  
    filehandle
  end

  def receive_data(data)
    (@buff = "") << data
    @buff.split($/).each do |l|
      # Don't log empty lines
      next if l.empty?
      receive_line(l)
    end
  end

  #
  # This method is called when the EventMachine receives a line from the file
  # descriptor, usually STDIN.  If the line reads "unbind and stop", the
  # instance tries to unbind, and then it stops the EventMachine.  If the line
  # reads "close filehandles and resume", then all filehandles are closed,
  # before the loop is resumed.
  #
  def receive_line(line)
    #
    # Make sure the line is a string
    #
    line = line.to_s

    #
    # Split the line into a domain name, and the rest of the line.  The domain is
    # always the first field.  This is supplied by the REMOTE USER so suitable
    # sanity checks have to be made.
    #
    # This "split" splits the line into two at the first group of spaces.
    #
    # irb(main):030:0> "a  b c".split(" ",2)
    # => ["a", " b   c"]
    #
    domain_name, line_without_domain_name = line.split(" ",2)

    #
    # Set up the filehandle as nil to force us to find it each time.
    #
    filehandle = nil

    #
    # Find our domain.  This finds www and non-www prefixes, and returns nil
    # unless the domain is sane.
    #
    domain = @domain_objects[domain_name]
    
    #
    # Make sure the domain has been found, and the Process UID/GID matches the
    # domain UID/GID, or it is root.
    #
    if domain and [0, domain.uid].include?(Process.uid) and [0, domain.gid].include?(Process.gid)
      #
      # Fetch the log filename
      #
      log_filename = File.expand_path(File.join(domain.log_dir, self.log_filename))

      #
      # Fetch the file handle, or open the logfile, as needed.
      #
      filehandle = self.filehandles.find{|fh| fh.is_a?(File) and fh.path == log_filename}

      #
      # Remove the filehandle from the arry (we'll add it back later)
      #
      self.filehandles.delete(filehandle) 

      #
      # If no filehandle was found, or the filehandle we've found is duff,
      # (re)-open it.
      #
      unless filehandle.is_a?(File) and not filehandle.closed?
        #
        # Make sure we don't open more than 50 file handles.
        #
        if self.filehandles.length >= self.max_filehandles
          other_filehandle = self.filehandles.pop
          other_filehandle.close unless other_filehandle.closed?
        end

        filehandle = open_log(log_filename, {:domain => domain, :uid => domain.uid, :gid => domain.gid, :sync => self.sync_io})
      end

    end

    if filehandle.is_a?(File) and not filehandle.closed?
      #
      # Add the filehandle onto our array.
      #
      self.filehandles << filehandle

      #
      # Write the log, but without the domain on the front.
      #
      filehandle.puts(line_without_domain_name)
    else
      warn "#{$0}: No file handle found -- logging to default file for #{domain.inspect}" if $VERBOSE and domain.is_a?(Symbiosis::Domain)

      #
      # Make sure the default filehandle is open.
      #
      if @default_filehandle.nil? or @default_filehandle.closed?
        warn "#{$0}: Opening default log file #{self.default_filename}" if $VERBOSE 
        @default_filehandle = open_log(self.default_filename, {:domain => domain, :uid => self.uid, :gid => self.gid})
      end

      if @default_filehandle.is_a?(File) and not @default_filehandle.closed?
        #
        # Write the unadulterated line to the default log.
        #
        @default_filehandle.puts(line)
      else 
        STDERR.puts line
      end
    end

  end

  #
  # Close all the file handles the class has open
  #
  def close_filehandles
    self.pause unless self.paused?

    ([@default_filehandle] + self.filehandles).flatten.each do |fh|
      #
      # Don't try and close things that aren't Files
      #
      next unless fh.is_a?(File)

      #
      # Don't try to close stuff that is already closed.
      #
      next if fh.closed?

      begin
        #
        # Flush to disc!
        #
        warn "#{$0}: Flushing and closing #{fh.path}" if $VERBOSE
        fh.flush
        fh.close
      rescue IOError
        # ignore
      end
    end

  end

  alias unbind close_filehandles

end
end

