
all: docs

man/symbiosis-configure-ips.man: sbin/symbiosis-configure-ips
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

man/%.man: ./bin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/encrypt_password.man man/encrypt_password.man  man/is-bytemark-ip.man  man/symbiosis-ip.man  man/symbiosis-test.man  man/which-backup-space.man man/symbiosis-configure-ips.man


clean:
	$(RM) -r man

test:
	cd test ; for i in t*.rb ; do [ -x $$i ] && ruby1.8 -I ../lib $$i ; true ; done

.PHONY: test clean all docs
 
