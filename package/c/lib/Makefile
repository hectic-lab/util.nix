CC = gcc
CFLAGS = -Wall -Wextra -std=c11
LDFLAGS = -L. -lmylib  # Link with your library

# Source files
LIB_SRC = mylib.c
LIB_OBJ = $(LIB_SRC:.c=.o)
TEST_SRC = test/test.c
TEST_OBJ = $(TEST_SRC:.c=.o)
TEST_BIN = test

# Build library
libmylib.a: $(LIB_OBJ)
	ar rcs $@ $^

# Build test executable
$(TEST_BIN): $(TEST_OBJ) libmylib.a
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

# Compile C files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Clean build artifacts
clean:
	rm -f $(LIB_OBJ) $(TEST_OBJ) $(TEST_BIN) libmylib.a
