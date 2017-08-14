
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

docs: man/symbiosis-email-dict-proxy.man  man/symbiosis-email-encrypt-passwords.man  man/symbiosis-email-poppassd.man

clean:
	$(RM) exim4/exim4.conf
	$(RM) exim4/exim4.conf.tmp
	$(RM) dovecot/dovecot.conf
	$(RM) dovecot/dovecot.conf.tmp
	$(RM) -r man

test:
	cd symbiosis/test.d/ && ruby -I ../../../common/lib -I ../../lib ts_email.rb
	make -C exim4/   test
	make -C dovecot/ test

all_tests: test
	cd symbiosis/test.d/ && ruby -I ../../../common/lib -I ../../lib ts_email_live.rb

.PHONY: clean docs all test

