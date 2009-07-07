
# This class attempts to categorize possible error exit statuses for system
# programs.  The values are taken from /usr/include/sysexits.h.
#
class SystemExit

  # Error numbers begin at EX__BASE to reduce the possibility of clashing with
  # other exit statuses that random programs may already return. 
  EX__BASE     = 64 

  # successful termination
  EX_OK        = 0 
  
  # The command was used incorrectly, e.g., with the wrong number of arguments,
  # a bad flag, a bad syntax in a parameter, or whatever.
  EX_USAGE     = 64 

  # The input data was incorrect in some way.  This should only be used for
  # user's data & not system files.
  EX_DATAERR   = 65
  
  # An input file (not a system file) did not exist or was not readable.  This
  # could also include errors like "No message" to a mailer (if it cared to
  # catch it).
  EX_NOINPUT   = 66 

  # The user specified did not exist.  This might be used for mail addresses or
  # remote logins.
  EX_NOUSER    = 67
  
  # The host specified did not exist.  This is used in mail addresses or
  # network requests.
  EX_NOHOST    = 68

  # A service is unavailable.  This can occur if a support program or file does
  # not exist.  This can also be used as a catchall message when something you
  # wanted to do doesn't work, but you don't know why.
  EX_UNAVAILABLE = 69 

  # An internal software error has been detected.  This should be limited to
  # non-operating system related errors as possible.
  EX_SOFTWARE    = 70

  # An operating system error has been detected.  This is intended to be used
  # for such things as "cannot fork", "cannot create pipe", or the like.  It
  # includes things like getuid returning a user that does not exist in the
  # passwd file.
  EX_OSERR     = 71 

  # Some system file (e.g., /etc/passwd, /etc/utmp, etc.) does not exist,
  # cannot be opened, or has some sort of error (e.g., syntax error).
  EX_OSFILE    = 72

  # A (user specified) output file cannot be created.
  EX_CANTCREAT = 73

  # An error occurred while doing I/O on some file.
  EX_IOERR     = 74 

  # temporary failure, indicating something that is not really an error.  In
  # sendmail, this means that a mailer (e.g.) could not create a connection,
  # and the request should be reattempted later.
  EX_TEMPFAIL  = 75 

  # the remote system returned something that was "not possible" during a
  # protocol exchange.
  EX_PROTOCOL  = 76 

  # You did not have sufficient permission to perform the operation.  This is
  # not intended for file system problems, which should use NOINPUT or
  # CANTCREAT, but rather for higher level permissions.
  EX_NOPERM    = 77

  # configuration error
  EX_CONFIG    = 78 

  # maximum listed value 
  EX__MAX      = 78 

  LOOKUP_TABLE = {
    EX_OK          => "Success",
    EX_USAGE       => "Command line usage error",
    EX_DATAERR     => "Data format error",
    EX_NOINPUT     => "Cannot open input",
    EX_NOUSER      => "Addressee unknown",
    EX_NOHOST      => "Host name unknown",
    EX_UNAVAILABLE => "Service unavailable",
    EX_SOFTWARE    => "Internal software error",
    EX_OSERR       => "System error",
    EX_OSFILE      => "Critical OS file missing",
    EX_CANTCREAT   => "Cannot create (user) output file",
    EX_IOERR       => "Input/output error",
    EX_TEMPFAIL    => "Temporary failure",
    EX_PROTOCOL    => "Remote error in protocol",
    EX_NOPERM      => "Permission denied",
    EX_CONFIG      => "Configuration error",
  }

  def to_s
    return "exit "+status.to_s unless LOOKUP_TABLE.has_key?(status)
    
    return LOOKUP_TABLE[status]
  end

end

  


