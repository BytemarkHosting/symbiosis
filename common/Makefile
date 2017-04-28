
all: docs

man/%.man:: ./bin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

man/%.man:: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

docs: man/symbiosis-encrypt-password.man  man/is-bytemark-ip.man  man/symbiosis-ip.man  man/symbiosis-test.man  man/which-backup-space.man man/symbiosis-configure-ips.man man/symbiosis-password-test.man man/symbiosis-ssl.man

clean:
	$(RM) -r man

test: test2.1 test2.3

test2.1:
	[ -z "`which ruby2.1`" ] ||  ruby2.1 -I lib ./bin/symbiosis-test  test.d/	

test2.3:
	[ -z "`which ruby2.3`" ] ||  ruby2.3 -I lib ./bin/symbiosis-test  test.d/	

.PHONY: test clean all docs

 
