
all: man

doc/index.html: lib
	rdoc -o rdoc lib/*

man/symbiosis-monit.man: sbin/symbiosis-monit
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/symbiosis-monit  --manual | txt2man -s 1 -t symbiosis-monit | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

man: man/symbiosis-monit.man

docs: man/symbiosis-monit.man doc/index.html

test: test2.1

test2.1:
	cd test.d
	[ -z "`which ruby2.1`" ] ||  (cd test.d && ruby2.1 -I . ts_monit.rb)

clean:
	$(RM) man/symbiosis-monit.man
	$(RM) -r man/
	$(RM) -r rdoc/

.PHONY: docs test all clean man test1.8 test1.9.1

