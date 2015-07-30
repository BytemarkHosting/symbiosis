
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/symbiosis-email-check-password.man man/symbiosis-email-dict-proxy.man

clean:
	$(RM) exim4/exim4.conf
	$(RM) exim4/exim4.conf.tmp
	$(RM) dovecot/dovecot.conf
	$(RM) dovecot/dovecot.conf.tmp
	$(RM) -r man

test:
	make -C exim4/   test
	make -C dovecot/ test

.PHONY: clean docs all test

