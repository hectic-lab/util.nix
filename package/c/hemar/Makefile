MODULE_big = hemar
OBJS = hemar.o
EXTENSION = hemar

DATA = $(wildcard *.sql)

HECTIC_CONFIG = hectic-config
PG_CONFIG = pg_config

PG_CFLAGS += $(shell $(HECTIC_CONFIG) --cflags)
PG_LDFLAGS += -Wl,-rpath,$(shell $(HECTIC_CONFIG) --libdir)
SHLIB_LINK += $(shell $(HECTIC_CONFIG) --libs)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
