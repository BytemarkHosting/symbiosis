
all: docs

doc/index.html: lib
	rdoc -o rdoc lib/*

man/bytemark-vhost-monit.man: sbin/bytemark-vhost-monit
	[ -d man ] || mkdir man
	RUBYLIB=./lib ./sbin/bytemark-vhost-monit  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t bytemark-vhost-monit | sed -e 's/\\\\fB/\\fB/' > man/bytemark-vhost-monit.man

docs: man/bytemark-vhost-monit.man doc/index.html


clean:
	$(RM) man/bytemark-vhost-monit.man
	$(RM) -r man/
	$(RM) -r rdoc/

