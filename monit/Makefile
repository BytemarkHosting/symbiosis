
all: man

doc/index.html: lib
	rdoc -o rdoc lib/*

man/symbiosis-monit.man: sbin/symbiosis-monit
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/symbiosis-monit  --manual | txt2man -s 1 -t symbiosis-monit | sed -e 's/\\\\fB/\\fB/' > man/symbiosis-monit.man

man: man/symbiosis-monit.man

docs: man/symbiosis-monit.man doc/index.html

test:
	cd test && ruby1.8 ts_monit.rb

clean:
	$(RM) man/symbiosis-monit.man
	$(RM) -r man/
	$(RM) -r rdoc/

.PHONY: docs test all clean man

