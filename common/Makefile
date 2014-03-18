
all: docs

man/symbiosis-configure-ips.man: sbin/symbiosis-configure-ips
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

man/symbiosis-password-test.man: sbin/symbiosis-password-test
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

man/%.man: ./bin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/symbiosis-encrypt-password.man  man/is-bytemark-ip.man  man/symbiosis-ip.man  man/symbiosis-test.man  man/which-backup-space.man man/symbiosis-configure-ips.man man/symbiosis-password-test.man


clean:
	$(RM) -r man

test: test1.9.1 test2.0

test1.9.1:
	ruby1.9.1 ./bin/symbiosis-test  test.d/	

test2.0:
	ruby2.0 ./bin/symbiosis-test  test.d/	

.PHONY: test clean all docs
 
