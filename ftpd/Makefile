
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/symbiosis-ftpd-check-password.man

clean:
	$(RM) -r man

test:
	cd test.d && ruby -I ../lib:../../common/lib tc_ftp_check_password.rb

.PHONY: clean docs all test

