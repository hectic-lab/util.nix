MODULE_big = hel
OBJS = hel.o
EXTENSION = hel
DATA = hel--0.1.sql

PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)

HECTIC_CONFIG = hectic-config

CFLAGS += $(shell $(HECTIC_CONFIG) --cflags)
LDFLAGS += $(shell $(HECTIC_CONFIG) --libs)

SHLIB_LINK := $(LIBS)

include $(PGXS)