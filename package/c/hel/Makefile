MODULE_big = hel
OBJS = hel.o
EXTENSION = hel
DATA = hel--0.1.sql

PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)

# Add hectic library path
CFLAGS += -I -lhectic

include $(PGXS)