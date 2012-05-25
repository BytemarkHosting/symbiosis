conf         := backup2l.conf
conf_tmp     := $(conf).tmp
snippets_dir := conf.d
snippets     := $(shell ls $$PWD/$(snippets_dir)/[0-9][0-9]-*.conf | sort)

all: $(conf)

$(conf): check
	@mv -fb $(conf_tmp) $(conf)

#
# Add an explicit dependency on the header, to make sure that the snippets
# directory has at least that bit.
#
$(conf_tmp): distclean Makefile $(snippets) 
	@for s in $(snippets) ; do \
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo "# $$s" >> $(conf_tmp)  ;\
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo >> $(conf_tmp)  ;\
	    cat $$s >> $(conf_tmp) ;\
	done

check: $(conf_tmp)
	@bash -c "set -e ; . $(conf_tmp)"

distclean:
	@rm -f $(conf_tmp)

clean:
	@rm -f $(conf)

# We always want the temporary config to be remade.
.PHONY: $(conf_tmp) all clean distclean check

.PRECIOUS: $(conf)
