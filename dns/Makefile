
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	pod2man $< > $@

docs: man/symbiosis-dns-generate.man

clean:
	$(RM) -r man
