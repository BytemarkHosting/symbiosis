require 'symbiosis/domains'
require 'symbiosis/utils'
require 'eventmachine'

module Symbiosis
class ApacheLogger < EventMachine::Protocols::LineAndTextProtocol

  #
  # Set the Symbiosis::Domain prefix
  #
  def prefix=(p)
    @prefix = p
  end

  #
  # Return our array of filehandles
  #
  def filehandles
    @filehandles ||= []
  end

  #
  # Return the log filename
  #
  def log_filename
    @log_filename ||= "access.log"
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
    @max_filehandles ||= 50
  end

  #
  # Set the maximum number of filehandles we can have open at any one time.
  # Defaults to 50.
  #
  def max_filehandles=(n)
    @max_filehandles = n
  end

  def sync_io
    (@sync_io === true) || false
  end

  def sync_io=(tf)
    @sync_io = (tf === true)
  end

  def default_filehandle_opts
    @default_filehandle_opts ||= {:mode => 0644}
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
    # Magic lines to use when testing.
    #
    case line
      when "unbind and stop"
        unbind_and_stop
      when "close filehandles and resume"
        close_filehandles_and_resume
    end

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
    domain =  Symbiosis::Domains.find(domain_name, @prefix || "/srv")

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
          other_filehandle.close
        end

        begin
          #
          # Set up a couple of things before we open the file.  This will make
          # sure the ownerships are correct.
          #
          begin
            warn "#{$0}: Creating directory #{File.dirname(log_filename)}" if $VERBOSE 
            Symbiosis::Utils.mkdir_p(File.dirname(log_filename), :uid => domain.uid, :gid => domain.gid, :mode => 0755)
          rescue Errno::EEXIST
            # ignore
          end

          warn "#{$0}: Opening log file #{log_filename}" if $VERBOSE 
          filehandle = Symbiosis::Utils.safe_open(log_filename, "a+", :mode => 0644, :uid => domain.uid, :gid => domain.gid)
          filehandle.sync = self.sync_io

        rescue StandardError => err
          filehandle = nil
          warn "#{$0}: Caught #{err}" if $VERBOSE
        end

      end

    end

    if filehandle.nil? 
      warn "#{$0}: No file handle found -- logging to default file for #{domain.inspect}" if $VERBOSE and domain.is_a?(Symbiosis::Domain)

      #
      # Make sure the default filehandle is open.
      #
      if default_filehandle.nil? or default_filehandle.closed?
        warn "#{$0}: Opening default log file #{self.default_log}" if $VERBOSE 
        default_filehandle = Symbiosis::Utils.safe_open(self.default_log,'a+', self.default_filehandle_opts)
        default_filehandle.sync = self.sync_io
      end

      #
      # Write the unadulterated line to the default log.
      #
      default_filehandle.puts(line)

    else
      #
      # Add the filehandle onto our array.
      #
      self.filehandles << filehandle

      #
      # Write the log, but without the domain on the front.
      #
      filehandle.puts(line_without_domain_name)
    end

  end

  #
  # Close all the file handles the class has open
  #
  def close_filehandles(resume_afterwards = false)
    self.pause unless self.paused?

    self.filehandles.flatten.each do |fh|
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

    self.resume if (resume_afterwards === true)
  end

  def close_filehandles_and_resume
    close_filehandles(true)
  end

  def unbind
    self.close_filehandles
  end

  def unbind_and_stop
    self.unbind
    EM.stop
  end

end
end

