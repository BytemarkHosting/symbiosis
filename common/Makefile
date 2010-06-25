
all: docs

man/%.man: ./bin/%
	[ -d man ] || mkdir man
	$<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

docs: man/encrypt_password.man

clean:
	$(RM) -r man
