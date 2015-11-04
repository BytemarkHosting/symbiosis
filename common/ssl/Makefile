#!/usr/bin/make -f

HOSTNAME ?= $(shell hostname -f)
tempext  := symbiosis.$(shell echo $$$$)

check: check_crt check_combined

check_combined: ssl.combined 
	@if [ "$$(openssl x509 -noout -modulus -in $< 2>/dev/null )" = "$$(openssl rsa -noout -modulus -in $<)" ] ; then \
		echo "I: Successfully verified that the key and certificates in $< match." ; \
	else \
		echo "W: The key and certificates in $< do not match." ; \
	fi
	@if ( openssl verify -CAfile ssl.combined ssl.combined 2>&1 > /dev/null ) ; then \
    echo "I: Successfully verified the certificate (and bundle) in $<."; \
	else \
     echo "W: Warning: Cannot verify $< -- maybe a bundle is missing?" ; \
	fi

check_crt: ssl.crt ssl.key
	@if ( openssl x509 -in ssl.bundle -noout > /dev/null 2>&1 ) ; then \
		if ( openssl verify -CAfile ssl.bundle $< > /dev/null 2>&1 ) ; then \
    	echo "I: Successfully verified $< with ssl.bundle."; \
		else \
			echo "W: Cannot verify $< using ssl.bundle.  Maybe the bundle is wrong?" ; \
		fi ; \
	elif ( openssl verify -CAfile $< $< > /dev/null 2>&1  ) ; then \
   	echo "I: The certificate in $< is self-signed."; \
	else \
		echo "W: Cannot verify $<.  Maybe a bundle is missing?" ; \
	fi
	@if [ "$$(openssl x509 -noout -modulus -in ssl.crt)" = "$$(openssl rsa -noout -modulus -in ssl.key)" ] ; then \
		echo "I: Successfully verified that ssl.key matches the certificate in ssl.crt" ; \
	else \
		echo "W: The key in ssl.key does not match the certificate in ssl.crt." ; \
	fi

ssl.crt:
	@if [ -z "$(HOSTNAME)" ]  ; then \
		echo "W: Could not determine hostname"; \
		exit 1 ; \
	fi
	@openssl req -subj "/C=GB/ST=England/L=York/CN=$(HOSTNAME)" -new \
		-x509 -days 3650 -nodes -out ssl.crt.$(tempext) -newkey rsa:2048 \
		-keyout ssl.key.$(tempext) -sha256 > /dev/null
	@mv ssl.crt.$(tempext) ssl.crt
	@mv ssl.key.$(tempext) ssl.key
	@echo "I: Created a self-signed certificate and key."

ssl.key: ssl.crt
	@chmod 600 ssl.key

ssl.combined: ssl.crt ssl.key 
	@cp ssl.crt ssl.combined.$(tempext)
	@if ( openssl x509 -in ssl.bundle -noout > /dev/null 2>&1 ) ; then \
		if ( openssl verify -CAfile ssl.bundle ssl.crt > /dev/null 2>&1 ) ; then \
			cat ssl.bundle >> ssl.combined.$(tempext) ; \
		else \
			echo "W: Cannot verify ssl.crt using ssl.bundle." ; \
		fi ; \
	fi
	@cat ssl.key >> ssl.combined.$(tempext)
	@mv ssl.combined.$(tempext) ssl.combined
	@chmod 600 ssl.combined
	@echo "I: Created combined certificate, bundle, and key."

clean:
	@$(RM) -v ssl.crt.symbiosis.[0-9]* ssl.key.symbiosis.[0-9]* ssl.combined.symbiosis.[0-9]* 

.PHONY: clean check_crt check_combined check
