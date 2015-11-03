

# hostname := $(shell hostname -f)
tempext  := symbiosis.$(shell echo $$$$)

check: ssl.combined ssl.crt ssl.key
	@if [ "$$(openssl x509 -noout -modulus -in ssl.crt)" = "$$(openssl rsa -noout -modulus -in ssl.key)" ] ; then \
		echo "I: Successfully verified that ssl.key matches ssl.crt." ; \
	else \
		echo "W: The key in ssl.key does not work for ssl.crt." ; \
	fi

	@if ( openssl verify -CAfile ssl.combined ssl.combined 2>&1 > /dev/null ) ; then \
    echo "I: Successfully verified $<."; \
	else \
     echo "W: Warning: Cannot verify $< -- maybe a bundle is missing?" ; \
	fi

ssl.crt:
	@if [ -z "$(hostname)" ]  ; then \
		echo "W: Could not determine hostname"; \
		exit 1 ; \
	fi
	@openssl req -subj "/C=GB/ST=England/L=York/CN=$(hostname)" -new \
		-x509 -days 3650 -nodes -out ssl.crt.$(tempext) -newkey rsa:2048 \
		-keyout ssl.key.$(tempext) -sha256 > /dev/null
	@mv ssl.crt.$(tempext) ssl.crt
	@mv ssl.key.$(tempext) ssl.key
	@echo "I: Created a self-signed certificate and key."

ssl.key: ssl.crt

ssl.combined: ssl.crt
	@cp $< ssl.combined.$(tempext)
	@if ( openssl x509 -in ssl.bundle -noout > /dev/null 2>&1 ) ; then \
		if ( openssl verify -CAfile ssl.bundle $< > /dev/null 2>&1 ) ; then \
			cat ssl.bundle >> ssl.combined.$(tempext) ; \
		else \
			echo "W: Cannot verify $< using ssl.bundle." ; \
		fi ; \
	fi
#
# Check to see if the combined cert can verify itself
#
	@mv ssl.combined.$(tempext) ssl.combined
	@echo "I: Created combined bundle and certificate."

clean:
	@$(RM) -v ssl.crt.symbiosis.[0-9]* ssl.key.symbiosis.[0-9]* ssl.combined.symbiosis.[0-9]* 

.PHONY: clean
