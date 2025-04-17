EXTENSION ?= postgreact
EXTENSION_VERSION ?= 1.0

# INFO(nrv): just in case idk how pgxs Makefile and shit all work
EXTVERSION = $(EXTENSION_VERSION)

MODULE_big = $(EXTENSION)
DATA = $(EXTENSION)--$(EXTENSION_VERSION).sql
OBJS = $(EXTENSION).o 
PG_CONFIG = pg_config

$(BUILD_DIR)/$(EXTENSION).control:
	sed "s/@EXTENSION_VERSION@/$(EXTVERSION)/g" $(EXTENSION).control.in > $@

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
