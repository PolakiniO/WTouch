CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -pedantic -O2
TARGET ?= wtouch_c

all: $(TARGET)

$(TARGET): wtouch.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f $(TARGET)

.PHONY: all clean
