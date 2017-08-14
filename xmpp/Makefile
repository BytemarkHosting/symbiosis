
all: man/symbiosis-xmpp-configure.man

docs: all

test:
	@echo "I: no tests defined for this package"

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

clean:
	$(RM) -r man

.PHONY: clean nop test docs
