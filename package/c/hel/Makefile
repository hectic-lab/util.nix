MODULE_big = hel
OBJS = hel.o
EXTENSION = hel

DATA = $(wildcard *.sql)

PG_CONFIG = pg_config

HECTIC_CONFIG = hectic-config

CFLAGS += $(shell $(HECTIC_CONFIG) --cflags)
LDFLAGS += $(shell $(HECTIC_CONFIG) --libs)

SHLIB_LINK := $(LIBS)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)