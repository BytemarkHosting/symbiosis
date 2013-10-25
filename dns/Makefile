
all: docs

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/symbiosis-dns-generate.man

test: test1.8 test1.9.1

test1.8:
	ruby1.8 ../common/bin/symbiosis-test test.d

test1.9.1:
	ruby1.9.1 ../common/bin/symbiosis-test test.d

clean:
	$(RM) -r man

.PHONY: clean docs all test test1.8 test1.9.1
