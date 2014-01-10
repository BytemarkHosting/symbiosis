program      := $(notdir $(CURDIR))
conf         := $(program).conf
conf_tmp     := $(conf).tmp
snippets_dir := symbiosis.d
snippets     := $(shell find $(CURDIR)/$(snippets_dir) -mindepth 1 -regextype posix-basic -type f -regex '.*/[a-z0-9][a-z0-9-]\+' | sort) 

ifeq ($(program),dovecot)
test_args = -a -c $(conf_tmp)
else ifeq ($(program),exim4)
test_args = -bV -C $(conf_tmp)
endif

all: $(conf)

$(conf): test
	@mv -fb $(conf_tmp) $(conf)

#
# Add an explicit dependency on the header, to make sure that the snippets
# directory has at least that bit.
#
$(conf_tmp): distclean Makefile $(snippets) $(CURDIR)/$(snippets_dir)/00-header
	@touch $(conf_tmp)
	@for s in $(snippets) ; do \
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo "# $$s" >> $(conf_tmp)  ;\
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo >> $(conf_tmp)  ;\
	    cat $$s >> $(conf_tmp) ;\
	done

test: $(conf_tmp)
	@/usr/sbin/$(program) $(test_args) > /dev/null

distclean:
	@rm -f $(conf_tmp)

clean:
	@rm -f $(conf)

# We always want the temporary config to be remade.
.PHONY: $(conf_tmp) clean distclean test

.PRECIOUS: $(conf)
