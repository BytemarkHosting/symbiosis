
all: docs

man/%.man: ./bin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/is-bytemark-ip.man man/which-backup-space.man

clean:
	$(RM) -r man

.PHONY: all docs clean
