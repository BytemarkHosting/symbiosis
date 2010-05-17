
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/exim_rewrite_scan.man man/dovecot_checkpassword.man

clean:
	$(RM) man/exim_rewrite_scan.man
	$(RM) exim4/exim4.conf
	$(RM) exim4/exim4.conf.tmp
	$(RM) dovecot/dovecot.conf
	$(RM) dovecot/dovecot.conf.tmp
	$(RM) -r man
