# Builds tink_tcp.hdll (bytecode) and tink_tcp_uv.o (HL/C).
# Requires HashLink headers/libs and libuv.

HL_PREFIX ?= /usr/local
HL_INCLUDE ?= $(HL_PREFIX)/include
HL_LIB ?= $(HL_PREFIX)/lib
UV_INCLUDE ?= /opt/homebrew/include
UV_LIB ?= /opt/homebrew/lib

CFLAGS ?= -Wall -O3 -std=c11 -fvisibility=hidden
ARCH ?= $(shell uname -m)

.PHONY: all clean

all: tink_tcp.hdll tink_tcp_uv.o

tink_tcp_uv.o: tink_tcp_uv.c
	$(CC) $(CFLAGS) -arch $(ARCH) -I$(HL_INCLUDE) -I$(UV_INCLUDE) -c -o $@ $<

tink_tcp.hdll: tink_tcp_uv.o
	$(CC) $(CFLAGS) -arch $(ARCH) -shared -o $@ $< \
		-L$(HL_LIB) -lhl -L$(UV_LIB) -luv \
		-install_name @rpath/tink_tcp.hdll \
		-rpath @executable_path -rpath $(HL_LIB)

clean:
	rm -f tink_tcp_uv.o tink_tcp.hdll
