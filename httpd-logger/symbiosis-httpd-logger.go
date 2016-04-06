//
// This is drop-in replacement for the symbiosis-http-logger
// script which is distributed with Symbiosis.
//
// The command-line flags are 100% compatible with the old implementation
// even though they are largely ignored.
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
	var sync_text = "Should we immediately sync to disk?"
	var sync_long *bool = flag.Bool("sync", false, sync_text)
	var sync_short *bool = flag.Bool("s", false, sync_text)

	//
	// Define command-line flags: -f/--max-files
	//
	var files_text = "Maxium number of log files to hold open"
	var files_long *int = flag.Int("files", 0, files_text)
	var files_short *int = flag.Int("f", 0, files_text)

	//
	// Define command-line flags: -l/--log-name
	//
	var log_text = "The name of the logfile to write"
	var log_long *string = flag.String("log-name", "access.log", log_text)
	var log_short *string = flag.String("l", "access.log", log_text)

	//
	// Define command-line flags: -v/--verbose
	//
	var verbose_text = "Should we be verbose?"
	var verbose_long *bool = flag.Bool("verbose", false, verbose_text)
	var verbose_short *bool = flag.Bool("v", false, verbose_text)

	//
	// Define command-line flags: -u/-g
	//
	var uid_text = "Set the UID -- privileges are dropped if this is set"
	var g_uid *int = flag.Int("u", 0, uid_text)
	var gid_text = "Set the GID -- privileges are dropped if this is set"
	var g_gid *int = flag.Int("g", 0, gid_text)

	//
	// Perform the actual parsing of the arguments.
	//
	flag.Parse()

	//
	// Handle the possible short/long alternatives.
	//
	sync_flag := *sync_long || *sync_short
	verbose_flag := *verbose_long || *verbose_short
	files_count := (*files_long + *files_short)

	//
	// The name of the per-domain logfile to write beneath
        // directories such as /srv/example.com/public/logs/
	//
	default_log := "access.log"

	//
	// If we've been given a different name via -l|--log-file
	// then use that instead.
	//
	if (*log_long != "access.log") || (*log_short != "access.log") {
		if *log_long == "access.log" {
			default_log = *log_short
		} else {
			default_log = *log_long
		}
	}

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
	if verbose_flag {
		fmt.Fprintln(os.Stderr, "sync:", sync_flag)
		fmt.Fprintln(os.Stderr, "verbose:", verbose_flag)
		fmt.Fprintln(os.Stderr, "files:", files_count)
		fmt.Fprintln(os.Stderr, "uid:", *g_uid)
		fmt.Fprintln(os.Stderr, "gid:", *g_gid)
		fmt.Fprintln(os.Stderr, "default_file:", default_file)
		fmt.Fprintln(os.Stderr, "log_file:", *log_long)
		fmt.Fprintln(os.Stderr, "log_file:", *log_short)
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
			handles[default_file], _ = os.OpenFile(default_file, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0664)
			defer handles[default_file].Close()
		}

		//
		// Before we do anything else write the new entry to
		// the default logfile.
		//
		handles[default_file].WriteString(log + "\n")

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
			fmt.Fprintln(os.Stderr, "Received malformed request-line:", log)
			continue

		}
		host := match[1]
		rest := match[2]

		//
		// This is the path to the per-vhost directory
		//
		logfile := "/srv/" + host

		//
		// Stat the directory to see who owns it
		//
		stat, err := os.Stat(logfile)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Received request for vhost that doesn't exist:", err)
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
			handles[logfile], _ = os.OpenFile(logfile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0664)
			h = handles[logfile]
			defer h.Close()

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
			os.Chown(logfile, int(uid), int(gid))
		}

		//
		// Write the log-line, adding the newline which the
		// scanner removed.
		//
		h.WriteString(rest + "\n")
	}

	// Check for errors during `Scan`. End of file is
	// expected and not reported by `Scan` as an error.
	if err := scanner.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}

	//
	// Close all our open handles - shouldn't be required as the deferred
	// close will do the necessary.
	//
	for _, handle := range handles {
		handle.Close()
	}
	os.Exit(0)
}
