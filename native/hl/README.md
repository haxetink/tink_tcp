# HashLink native (`uv_shutdown`)

`hl.uv.Stream` has no half-close. This native exports `stream_shutdown` for `tink.tcp.internal.hl.UvExtras`, used when a sink ends (`end: true`).

Haxe binds it as `@:hlNative("tink_tcp", "stream_shutdown")`.

## How HL picks it up

| Mode | Artifact | Load / link |
|------|----------|-------------|
| **HL/JIT** (`--hl out.hl` + `hl out.hl`) | `tink_tcp.hdll` | At runtime, `hl` loads `tink_tcp.hdll` by the `@:hlNative` lib name (`tink_tcp`). Put the `.hdll` next to the `.hl` file, on `HL_STD_PATH`, or on the dynamic-library search path (`DYLD_LIBRARY_PATH` / `LD_LIBRARY_PATH`). |
| **HL/C** (`--hl out/main.c` + `cc …`) | `tink_tcp_uv.o` (or `.c`) | No `.hdll` load. Link the object (or compile the `.c`) into the final binary so `tink_tcp_stream_shutdown` is a normal C symbol. Also link `libhl`, `libuv`, and HashLink’s `uv` / `ssl` modules as usual. |

If the native is missing, shutdown falls back to a full close (breaks “write then read” patterns).

## Build

```sh
make -C native/hl
# optional overrides:
# make -C native/hl HL_PREFIX=/path/to/hashlink UV_INCLUDE=/usr/include UV_LIB=/usr/lib
```

Produces `tink_tcp.hdll` and `tink_tcp_uv.o`.

## HL/JIT

```sh
haxe ... --hl bin/hl/tests.hl
cp native/hl/tink_tcp.hdll bin/hl/
hl bin/hl/tests.hl
```

## HL/C

```sh
haxe ... --hl bin/hl/c/main.c
cc -O2 -o bin/hl/c/tests bin/hl/c/main.c native/hl/tink_tcp_uv.o \
  -I bin/hl/c -I "$HL/src" -I "$HL/include" \
  -L "$HL" -lhl "$HL/uv.hdll" "$HL/ssl.hdll" -luv \
  -Wl,-rpath,"$HL"
```

Adjust include/lib paths to your HashLink build. On Apple Silicon, Homebrew often ships HL/C libs only (no JIT `hl` binary).
