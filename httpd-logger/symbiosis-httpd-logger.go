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
	"flag"
	"fmt"
	"os"
	"os/signal"
	"regexp"
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
var files_count = 100

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
func setup_hup_handler() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGHUP)
	go func() {
		<-c
		close_logfiles()
	}()
}

//
// Close all of our open logfiles.
//
func close_logfiles() {
	for path, handle := range handles {
		handle.Close()
		handles[path] = nil
	}
	setup_hup_handler()
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
func safeOpen(path string) *os.File {

	//
	// If we have too many open files then close them all.
	//
	if len(handles) > files_count {
		for path, handle := range handles {
			handle.Close()
			handles[path] = nil
		}
	}

	//
	// Open the file.  If it fails report that.
	//
	handle, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		if verbose {
			fmt.Fprintln(os.Stderr, "Failed to open file:", path)
		}
		return nil
	}

	//
	//  Now stat the file, to make sure it isn't a symlink.
	//
	//  We don't want to blindly write to symlinks because that
	// can cause security issues.
	//
	fi, serr := os.Lstat(path)
	if serr != nil {
		if verbose {

			fmt.Println("Failed to stat the file", path, serr)
		}
		handle.Close()
		return nil
	}

	if fi.Mode()&os.ModeSymlink != 0 {
		fmt.Println("Cowardly refusing to write to symlinked file", path)
		handle.Close()
		return nil
	}

	return handle
}

//
// Return true if the path/file exists, false otherwise.
//
func exists(path string) (bool, error) {
	_, err := os.Stat(path)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return true, err
}

//
// The entry-point to our command-line tool.
//
func main() {

	//
	// Define command-line flags: -s/--sync
	//
	var sync_flag bool
	flag.BoolVar(&sync_flag, "s", false, "Open log files in synchronous mode")

	//
	// Define command-line flags: -f/--max-files
	//
	var files_count int
	flag.IntVar(&files_count, "f", 0, "Maxium number of log files to hold open")

	//
	// Define command-line flags: -l/--log-name
	//
	var default_log string
	flag.StringVar(&default_log, "l", "access.log", "The file name of the generated logs")

	//
	// Define command-line flags: -v/--verbose
	//
	var verbose bool
	flag.BoolVar(&verbose, "v", false, "Show verbose output")

	//
	// Define command-line flags: -u/-g
	//
	var uid_text = "Set the default owner when writing files"
	var g_uid *int = flag.Int("u", 0, uid_text)
	var gid_text = "Set the default group when writing files"
	var g_gid *int = flag.Int("g", 0, gid_text)

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
	//
	// The default is this:
	//
	default_file := "/var/log/apache2/zz-mass-hosting.log"
	if len(flag.Args()) > 0 {
		default_file = flag.Args()[0]
	}

	//
	// If being verbose then dump state of the parsed-flags to
	// the screen.  Most of these are ignored ..
	//
	if verbose {
		fmt.Fprintln(os.Stderr, "sync:", sync_flag)
		fmt.Fprintln(os.Stderr, "verbose:", verbose)
		fmt.Fprintln(os.Stderr, "files:", files_count)
		fmt.Fprintln(os.Stderr, "uid:", *g_uid)
		fmt.Fprintln(os.Stderr, "gid:", *g_gid)
		fmt.Fprintln(os.Stderr, "default_file:", default_file)
		fmt.Fprintln(os.Stderr, "log_file:", default_log)
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
	setup_hup_handler()

	//
	// Instantiate a scanner to read (unbuffered) input, line-by-line.
	//
	scanner := bufio.NewScanner(os.Stdin)

	//
	// A regular expression to split a line into "first word" and
	// "rest of line".
	//
	re := regexp.MustCompile("(?P<host>[^ \t]+)[ \t](?P<rest>.*)")

	//
	// Get input, unbuffered.
	//
	for scanner.Scan() {

		//
		// The log-line Apache sends us.
		//
		log := scanner.Text()

		//
		// Ensure that our default-file is open.
		//
		// This might be closed by the SIGHUP handler, for example.
		//
		if handles[default_file] == nil {
			handles[default_file] = safeOpen(default_file)
		}

		//
		// Before we do anything else write the new entry to
		// the default logfile.
		//
		if handles[default_file] != nil {
			handles[default_file].WriteString(log + "\n")
		}

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
		if match == nil {
			if verbose {

				fmt.Fprintln(os.Stderr, "Received malformed request-line:", log)
			}
			continue

		}
		host := match[1]
		rest := match[2]

		//
		// This is the path to the per-vhost directory
		//
		logfile :=  prefix + host

		//
		// Stat the directory to see who owns it
		//
		stat, err := os.Stat(logfile)
		if err != nil {
			if verbose {

				fmt.Fprintln(os.Stderr, "Received request for vhost that doesn't exist:", err)
			}
			continue
		}
		sys := stat.Sys()
		uid := sys.(*syscall.Stat_t).Uid
		gid := sys.(*syscall.Stat_t).Gid

		//
		// If the /logs/ directory doesn't exist then create it.
		//
		logfile += "/public/logs/"
		exists, _ := exists(logfile)
		if !exists {
			os.MkdirAll(logfile, 0775)
		}

		//
		// Now build up the complete logfile to the file we'll open
		//
		logfile += "/" + default_log

		//
		// Lookup the handle to the logfile in our cache.
		//
		h := handles[logfile]

		//
		// If that failed then this is the first time we've written
		// here, so we need to open the file.
		//
		if h == nil {
			handles[logfile] = safeOpen(logfile)
			h = handles[logfile]

			//
			// If we've been given a UID/GID explicitly
			// then we'll use them.
			//
			// If not we match the UID/GID of the top-level
			// /srv/$domain directory, which we found earlier.
			//
			if *g_uid != 0 {
				uid = uint32(*g_uid)
			}
			if *g_gid != 0 {
				gid = uint32(*g_gid)
			}

			// Ensure the UID/GID of the logfile match that on the
			// virtual-hosts' directory
			if h != nil {
				h.Chown(int(uid), int(gid))
			}
		}

		//
		// Write the log-line, adding the newline which the
		// scanner removed.
		//
		if h != nil {
			h.WriteString(rest + "\n")
		}
	}

	// Check for errors during `Scan`. End of file is
	// expected and not reported by `Scan` as an error.
	if err := scanner.Err(); err != nil {
		if verbose {

			fmt.Fprintln(os.Stderr, "error:", err)
		}
		os.Exit(1)
	}

	//
	// Close all our open handles.
	//
	close_logfiles()
	os.Exit(0)
}
