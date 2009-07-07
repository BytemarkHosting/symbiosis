
all: docs

man/exim_rewrite_scan.man: sbin/exim_rewrite_scan
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/exim_rewrite_scan  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t exim_rewrite_scan | sed -e 's/\\\\fB/\\fB/' > man/exim_rewrite_scan.man

docs: man/exim_rewrite_scan.man

clean:
	$(RM) man/exim_rewrite_scan.man
	$(RM) -r man
