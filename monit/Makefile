
all: docs

doc/index.html: lib
	rdoc -o rdoc lib/*

man/symbiosis-monit.man: sbin/symbiosis-monit
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/symbiosis-monit  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t symbiosis-monit | sed -e 's/\\\\fB/\\fB/' > man/symbiosis-monit.man

docs: man/symbiosis-monit.man doc/index.html


clean:
	$(RM) man/symbiosis-monit.man
	$(RM) -r man/
	$(RM) -r rdoc/

