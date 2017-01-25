//
// This is drop-in replacement for the symbiosis-http-logger
// script which is distributed with Symbiosis.
//
// The command-line flags are 100% compatible with the old implementation
// even though they are largely ignored.
//
//
// Security Concerns
// -----------------
//
// This might be running as root.  Input such as this will create
// /etc/public/logs/accsss.log:
//
//    ../etc foo bar baz
//
// In the real world this isn't a concern, a request to Apache wouldn't
// get as far as our logger:
//
//   curl -H "Host: ../etc" http://example.vm.bytemark.co.uk/
//   -> HTTP 400
//   -> Bad Request
//
// Since the user can't start this as root, unless already root, or
// inject intput into the Apache-owned pipe this is not a concern.
//
// Suggested solution?  Filter ".." from host-names.  At the moment
// that isn't done, by the rationale above.
//
// Steve
// --
//

package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
)

//
// Hash of filehandles, so we can avoid having to open each
// access.log every time we receive a new entry.
//
// This is global because we have to access it both in
// our main-loop and also from our signal-handler
//
// The key to the hash is the path to the file on-disk, with
// the value containing the handle object.
//
var handles = make(map[string]*os.File)

//
// The number of files we'll keep open at any one time.
//
// This may be changed by a command-line flag.
//
var filesCount = 100

//
// Are we running verbosely?
//
// This may be changed by a command-line flag.
//
var verbose = false

//
// Setup a handler for SIGHUP which will close all of our
// open files.
//
// Every day /etc/cron.daily/symbiosis-httpd-rotate-logs will
// send such a signal.
//
func setupHupHandler() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGHUP)
	go func() {
		<-c
		closeLogfiles()
	}()
}

//
// Close all of our open logfiles.
//
func closeLogfiles() {
	for path, handle := range handles {
		handle.Close()
		handles[path] = nil
	}
	setupHupHandler()
}

//
// Open a file - and ensure that it is not a symlink
//
// This function requires a little bit of explanation, because it doesn't
// work the way that it should.  Ideally we'd opne the file, then run a
// stat against the handle.  However in wonderful golang this doesn't work.
//
// You can open a file, and then stat the handle, but you will get a result
// which doesn't allow you to determine if the target is a symlink or not.
//
// This means you're reduced to stating on the file-path, via the `os.Lstat`
// function.  The problem here is that this is racy:
//
//   1.  Test if file is symlink.
//
//   2.  Open file.
//
// A racy-attacker could switch the result at point 1.5.  As a compromise
// we open the file, then run the check.  This means that we can't be
// switched in the simple way - if a symlink is swapped in then our
// existing/open handle won't point to it.
//
// You can prove this by running two terminals:
//
//    one: cat > foo
//
// Then in the other:
//
//    two: rm foo; ln -s /etc/passwd foo
//
// You will not overwrite the file.
//
// And on that note let us safely open a file.
//
func safeOpen(path string, mode os.FileMode, uid uint32, gid uint32, sync bool) *os.File {

	//
	// If we have too many open files then close them all.
	//
	if len(handles) > filesCount {
		for path, handle := range handles {
			handle.Close()
			handles[path] = nil
		}
	}

	//
	// Set the flags we want when creating the file
	//
	var openFlags = os.O_CREATE | os.O_APPEND | os.O_WRONLY

	if sync {
		openFlags = openFlags | os.O_SYNC
	}

	//
	// Open the file.  If it fails report that.  By default the file is set to
	// owner r/w only but this will get changed later where necessary.
	//
	handle, err := os.OpenFile(path, openFlags, os.FileMode(mode))

	if err != nil {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "Failed to open file:", path, err)
		}
		return nil
	}

	//
	//  Now stat the file, to make sure it isn't a symlink.
	//
	//  We don't want to blindly write to symlinks because that
	// can cause security issues.
	//
	fi, err := os.Lstat(path)
	if err != nil {
		if verbose {

			fmt.Fprintln(os.Stderr, os.Args[0], "Failed to stat the file", path, err)
		}
		handle.Close()
		return nil
	}

	if fi.Mode()&os.ModeSymlink != 0 {
		if verbose {

			fmt.Fprintln(os.Stderr, os.Args[0], "Cowardly refusing to write to symlinked file", path)
		}
		handle.Close()
		return nil
	}

	// Set the UID/GID of the logfile
	err = handle.Chown(int(uid), int(gid))
	if err != nil && verbose {

		fmt.Fprintln(os.Stderr, os.Args[0], "Failed to change ownership on file", path, err)
	}

	// Set the mode of the logfile
	err = handle.Chmod(mode)
	if err != nil && verbose {

		fmt.Fprintln(os.Stderr, os.Args[0], "Failed to change mode on file", path, err)
	}

	return handle
}

//
// Make directories in with as little race as possible.
//
// This function takes a directory path, finds the first existing member of the
// path, and then creates all the subdirectories using the same ownerships and
// permissions of the first member.
//
// It will not create directories inside directories owned by users/groups <
// 1000
//
func safeMkdir(dir string) error {

	//
	// Resolve the path into an absolute one.
	//
	parent, err := filepath.Abs(dir)
	if err != nil {
		return err
	}

	//
	// Check the parent.
	//
	lstatParent, err := os.Lstat(parent)

	//
	// If an error is returned (other than ENOEXIST) then raise it.
	//
	if err != nil && !os.IsNotExist(err) {
		return err
	}

	//
	// If the stat comes back non-nil, it found something.
	//
	if lstatParent != nil {
		if lstatParent.IsDir() {
			//
			// Nothing to do!
			//
			return nil
		}
		//
		// Awooga, something already in the way.
		//
		return os.ErrExist
	}

	//
	// Break down the directory until we find one that exists.
	//
	stack := []string{}

	//
	// The lstatParent is still nil from before.
	//
	for lstatParent == nil {
		//
		// This sticks our parent on the *front* of the stack, i.e. prepend rather
		// than append!
		//
		stack = append([]string{parent}, stack...)
		parent, _ = filepath.Split(parent)
		parent, err = filepath.Abs(parent)
		if err != nil {
			return err
		}
		lstatParent, err = os.Lstat(parent)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
	}

	//
	// Stat the parent directory owner/uid.
	//
	sys := lstatParent.Sys()
	var uid, gid uint32

	if statT, ok := sys.(*syscall.Stat_t); ok {
		uid = statT.Uid
		gid = statT.Gid
	} else {
		return errors.New("Could not determine UID/GID")
	}

	mode := lstatParent.Mode()

	//
	// Don't create directories in directories owned by system owners.
	//
	if uid < 1000 {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "Refusing to create directory for system user", uid)
		}
		return os.ErrPermission
	}

	if gid < 1000 {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "Refusing to create directory for system group", gid)
		}
		return os.ErrPermission
	}

	//
	// Create our stack of directories in real life.
	//
	for _, sdir := range stack {
		err = os.Mkdir(sdir, os.FileMode(mode))

		//
		// If an error is returned, and that is because there is something already
		// there, we can continue if it is a directory, otherwise raise the alert!
		//
		if err != nil {
			if os.IsExist(err) {
				lstatSdir, _ := os.Lstat(sdir)

				if lstatSdir.IsDir() {
					continue
				}
			}
			return err
		}

		//
		// Now try and lchown this new directory.  There is a TOCTOU race condition
		// here if Mallory manages to replace our newly created directory with
		// something else in the mean time, so we try to minimise this by using
		// lchown
		//
		err = os.Lchown(sdir, int(uid), int(gid))

		if err != nil {
			return err
		}

		//
		// Sadly golang is missing lchmod, so we're just going to use chmod
		// instead.  Arse.
		//
		err = os.Chmod(sdir, mode)

		if err != nil {
			return err
		}
	}

	return nil
}

/*
	Write the log line to the correct file.
*/
func writeLog(prefix string, host string, log string, filename string, syncFlag bool) (terr error) {

	//
	// We build up the logfile name from the prefix, host, and filename args.
	//
	logdir := filepath.Join(prefix, host)

	//
	// Resolve any symlinks to the true path.  This raises an error if the path
	// doesn't exist.  This is important as it prevents deleted domains from re-appearing.
	//
	logdir, err := filepath.EvalSymlinks(logdir)

	if err != nil {
		return err
	}

	//
	// If the hostname is not empty, then we need to add public/logs to the path.
	//
	if host != "" {
		logdir = filepath.Join(logdir, "public", "logs")
	}

	//
	// Now build up the complete logfile to the file we'll open
	//
	logfile := filepath.Join(logdir, filename)

	//
	// Lookup the handle to the logfile in our cache.
	//
	h := handles[logfile]

	//
	// If that failed then this is the first time we've written
	// here, so we need to open the file.
	//
	if h == nil {
		//
		// Now make sure our directory exists
		//
		if err = safeMkdir(logdir); err != nil {
			return err
		}

		//
		// Stat the directory to see who owns it
		//
		stat, err := os.Lstat(logdir)
		if err != nil {
			return err
		}

		sys := stat.Sys()
		var uid, gid uint32

		if statT, ok := sys.(*syscall.Stat_t); ok {
			uid = statT.Uid
			gid = statT.Gid
		} else {
			return errors.New("Could not determine UID/GID for log directory " + logdir)
		}

		//
		// We match the UID/GID/mode of the handle to the top-level /srv/$domain
		// directory, which we found earlier.
		//
		// Remove the executable and non-permissions bits.
		//
		mode := stat.Mode() & (os.ModePerm &^ 0111)

		handles[logfile] = safeOpen(logfile, mode, uid, gid, syncFlag)
		h = handles[logfile]
	}

	//
	// If the handle is still nil, error at this point.
	//
	if h == nil {
		return errors.New("Could not find filehandle for log file " + logfile)
	}

	//
	// Write the log-line, adding the newline which the
	// scanner removed.
	//
	h.WriteString(log + "\n")

	return nil
}

//
// The entry-point to our command-line tool.
//
func main() {
	//
	// Define command-line flags: -s (this is a no-op now)
	//
	var syncFlag bool
	flag.BoolVar(&syncFlag, "s", false, "Open log files in synchronous mode")

	//
	// Define command-line flags: -f
	//
	var filesCount uint
	flag.UintVar(&filesCount, "f", 50, "Maxium number of log files to hold open")

	//
	// Define command-line flags: -l
	//
	var defaultFilename string
	flag.StringVar(&defaultFilename, "l", "access.log", "The file name of the generated logs")

	//
	// Define command-line flags: -v
	//
	flag.BoolVar(&verbose, "v", false, "Show verbose output")

	//
	// Define command-line flags: -u/-g (these are no-ops now)
	//
	var uidText = "Set the default owner when writing files"
	var gUID = flag.Uint("u", 0, uidText)
	var gidText = "Set the default group when writing files"
	var gGID = flag.Uint("g", 0, gidText)

	//
	// Allow a prefix to be set for testing
	//
	var prefix string
	flag.StringVar(&prefix, "p", "/srv", "Set the Symbiosis directory prefix")

	//
	// Perform the actual parsing of the arguments.
	//
	flag.Parse()

	//
	// Now we should have one final argument, which is the
	// name of the "default" logfile.
	//
	// In addition to writing per-vhost logfiles we'll copy
	// all logs to that particular file.
	var defaultLog string
	var err error

	if len(flag.Args()) > 0 {
		defaultLog, err = filepath.Abs(flag.Args()[0])

		if err != nil && verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "Failed to work out the default log path", defaultLog, err)
		}
	}

	//
	// The default is this:
	//
	if defaultLog == "" {
		defaultLog = "/var/log/apache2/zz-mass-hosting.log"
	}

	//
	// Change directory to our prefix
	//
	fh, err := os.Open(prefix)
	if err != nil {
		fmt.Fprintln(os.Stderr, os.Args[0], err)
		os.Exit(1)
	}

	err = fh.Chdir()
	if err != nil {
		fmt.Fprintln(os.Stderr, os.Args[0], err)
		os.Exit(1)
	}

	fh.Close()

	//
	// Sanity check flags
	//
	if (*gUID != 0 && *gGID == 0) || (*gUID == 0 && *gGID != 0) {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "UID and GID must be either both zero or both non-zero.")
		}
		*gUID = 0
		*gGID = 0
	}

	if filesCount < 1 {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "The maximum number of files to hold open must be greater than zero.")
		}
		filesCount = 50
	}

	//
	// If being verbose then dump state of the parsed-flags to
	// the screen.  Most of these are ignored ..
	//
	if verbose {
		fmt.Fprintln(os.Stderr, "sync:", syncFlag)
		fmt.Fprintln(os.Stderr, "verbose:", verbose)
		fmt.Fprintln(os.Stderr, "files:", filesCount)
		fmt.Fprintln(os.Stderr, "uid:", *gUID)
		fmt.Fprintln(os.Stderr, "gid:", *gGID)
		fmt.Fprintln(os.Stderr, "defaultLog:", defaultLog)
		fmt.Fprintln(os.Stderr, "defaultFilename:", defaultFilename)
		fmt.Fprintln(os.Stderr, "prefix:", prefix)
	}

	//
	// At this point we'd ideally change UID/GID to those supplied
	// on the command-line, however syscall.Setgid and syscall.Setuid
	// don't actually work(!)
	//
	// We're living in exciting times with golang, so we'll not worry
	// about it here.  Instead we'll set the UID/GID on the logfile(s)
	// at the time we open them.
	//

	//
	// Setup our SIGHUP handler.
	//
	// This is issued by the daily log-rotation-job, and should
	// ensure that we reopen any closed logfiles.
	//
	setupHupHandler()

	//
	// Instantiate a scanner to read (unbuffered) input, line-by-line.
	//
	scanner := bufio.NewScanner(os.Stdin)

	//
	// A regular expression to split a line into "hostname" and
	// "rest of line".
	//
	re := regexp.MustCompile(`([_a-zA-Z0-9-]+\.(?:[_a-zA-Z0-9-]+\.?)+) (.*)`)

	//
	// Split some stuff up to work out our "defaultPrefix" (i.e.
	// /var/log/apache2) and "defaultLogFilename" (i.e. "zz-mass-hosting.log")
	// so we can use our writeLog() function with these values.
	//
	defaultLogPrefix, defaultLogFilename := filepath.Split(defaultLog)

	// Get input, unbuffered.
	//
	for scanner.Scan() {

		//
		// The log-line Apache sends us.
		//
		log := scanner.Text()

		//
		// The line will contain the vhost-name as the initial
		// token, then the rest of the stuff that Apache generally
		// shows.
		//
		// Using our regular expression "parse" this.  If we
		// fail then we'll assume that we've been given bogus
		// input.
		//
		match := re.FindStringSubmatch(log)

		//
		// If we get a match, try and write it to a per-host log.
		//
		if match != nil {
			if err := writeLog(prefix, strings.ToLower(match[1]), match[2], defaultFilename, syncFlag); err != nil {
				if verbose {
					fmt.Fprintln(os.Stderr, os.Args[0], "Failed to write to per-domain log file for", strings.ToLower(match[1]), err)
				}
			} else {
				continue
			}
		}

		//
		// Write to the default log if writing to the per-host log failed.  The
		// host name is empty here to show that we're writing to the default log.
		//
		if err := writeLog(defaultLogPrefix, "", log, defaultLogFilename, syncFlag); err != nil {
			if verbose {
				fmt.Fprintln(os.Stderr, os.Args[0], "Failed to write to default log file", defaultLogFilename, err)
			}
		}
	}

	// Check for errors during `Scan`. End of file is
	// expected and not reported by `Scan` as an error.
	if err := scanner.Err(); err != nil {
		if verbose {
			fmt.Fprintln(os.Stderr, os.Args[0], "error:", err)
		}
		os.Exit(1)
	}

	//
	// Close all our open handles.
	//
	closeLogfiles()
	os.Exit(0)
}
