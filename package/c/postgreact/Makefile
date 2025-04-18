EXTENSION ?= postgreact
EXTENSION_VERSION ?= 1.0
EXTENSION_COMMENT ?= My first extension

MODULE_big = $(EXTENSION)
DATA = $(EXTENSION)--$(EXTENSION_VERSION).sql $(EXTENSION).control
OBJS = $(EXTENSION).o 
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

.PHONY: $(EXTENSION).control

$(EXTENSION).control:
	sed "s/@EXTENSION_VERSION@/$(EXTENSION_VERSION)/g; s/@EXTENSION_COMMENT@/$(EXTENSION_COMMENT)/g; s/@EXTENSION@/$(EXTENSION)/g" $(EXTENSION).control.in > $@

include $(PGXS)

# vim:wrap
