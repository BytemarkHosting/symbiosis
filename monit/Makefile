
all: man

doc/index.html: lib
	rdoc -o rdoc lib/*

man/symbiosis-monit.man: sbin/symbiosis-monit
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/symbiosis-monit  --manual | txt2man -s 1 -t symbiosis-monit | sed -e 's/\\\\fB/\\fB/' > man/symbiosis-monit.man

man: man/symbiosis-monit.man

docs: man/symbiosis-monit.man doc/index.html

test: test1.9.1 test2.1 test2.3

test1.9.1:
	cd test.d
	[ -z "`which ruby1.9.1`" ] || (cd test.d && ruby1.9.1 -I . ts_monit.rb)

test2.1:
	cd test.d
	[ -z "`which ruby2.1`" ] ||  (cd test.d && ruby2.1 -I . ts_monit.rb)

test2.3:
	cd test.d
	[ -z "`which ruby2.3`" ] ||  (cd test.d && ruby2.3 -I . ts_monit.rb)

clean:
	$(RM) man/symbiosis-monit.man
	$(RM) -r man/
	$(RM) -r rdoc/

.PHONY: docs test all clean man test1.8 test1.9.1

