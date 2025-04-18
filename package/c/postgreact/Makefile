MODULE_big = postgreact
OBJS = postgreact.o
EXTENSION = postgreact

DATA = $(wildcard *.sql)

PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
