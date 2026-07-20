# API2 Handler Overhaul — Task Map

## Goal (locked)

Hard-cut to:

```haxe
typedef IncomingConnection = {
  final source:RealSource;
  final local:Endpoint;
  final peer:Endpoint;
}
typedef Handler = IncomingConnection->IdealSource;

Client.connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise>;
Server.bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server>;

interface Server {
  var endpoint(get, never):Endpoint;
  function shutdown():Promise<Noise>;
}
```

**Client.connect Promise:** resolves when the TCP/TLS dial **succeeds**, rejects when it **fails**. Handler is started only after a successful connect. The Promise does **not** wait for the handler’s outbound pipe / session lifetime.

**Handler semantics:** returned `IdealSource` is piped to the peer (`pipeTo(sink, {end: true})`). Aborting without draining inbound `source` is out of scope.

**Server.bind:** takes `Handler` up front (no `connected` Signal). Returns a `Server` with `endpoint` + `shutdown` only.

## Decisions (locked)

- Keep TLS via `ConnectOptions` / `BindOptions`; bind stays on `Endpoint`
- Static platform-switched `Client.connect` (mirror `Server.bind`)
- **No** `OpenPort` type — bind returns `Server`
- **No** backward compatibility: remove old signatures/types in the same overhaul
- **No** traces of the previous API: delete `Connection`, `connected`, instance `Client` interface, dead `#if false` tests, README examples of the old shape, commented SysServer/runloop leftovers, etc. Internal duplex plumbing may exist but must not be named or exposed as the old public `Connection` API

## Shared plumbing

Platform code still has a private duplex (source + sink + endpoints). Add one shared runner:

```haxe
// e.g. tink.tcp.Session
static function run(source, sink, local, peer, app:Handler):Void // or Promise ignored by connect
  // app({source, local, peer}) -> IdealSource
  // -> pipeTo(sink, {end: true})
```

- **Client:** on dial success → start `Session.run` → **then** resolve connect `Promise` with `Noise` (or resolve immediately after starting run; do not await pipe). On dial failure → reject; never call handler.
- **Server:** on each accept → `Session.run` (fire-and-forget regarding bind’s Promise; bind’s Promise is only listen success/failure).

Delete public `src/tink/tcp/Connection.hx`; rename/inline platform wrappers so nothing public still looks like the old `Connection` interface.

## Protocol

Agents work **strictly in order** T1…T10: implementor completes a task → reviewer signs off in that task’s agent log → next task. Do not start Tn+1 until reviewer approves Tn.

**Overhaul status:** complete (T1–T10 signed off). Residual env/platform TODOs (HL runtime, cpp/`linc_uv`, eval_tls, cpp DNS/ALPN) are outside this overhaul.

---

## Task list

### T1 — Public types; delete old API surface

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/Client.hx`, `src/tink/tcp/Server.hx`, new `Handler.hx` (or colocated typedefs); **delete** `src/tink/tcp/Connection.hx`; strip `Server.hx` commented runloop/SysServer dead code

#### Implementor checklist

- [x] Add `IncomingConnection`, `Handler`
- [x] `Client.connect(to, app, ?options):Promise<Noise>` — static `#if` dispatch only (no `interface Client`, no constructible client classes as the public entry)
- [x] `Server.bind(to, app, ?options):Promise<Server>` — `Server` has `endpoint` + `shutdown` only; **no** `connected`, **no** `OpenPort`
- [x] Keep `ConnectOptions` / `BindOptions`
- [x] Delete `Connection` and every public reference to it
- [x] No shims, deprecations, or dual APIs

#### Reviewer checklist

- [x] Signatures match goal (connect settles on dial; bind → `Server`)
- [x] Zero public remnants of old API (`Connection`, `connected`, instance `Client`)
- [x] No `OpenPort`

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Added `Handler.hx` (`IncomingConnection`, `Handler`). Rewrote `Client` as static `#if` dispatch `connect(to, app, ?options):Promise<Noise>`; rewrote `Server.bind(to, app, ?options)` returning `Server` with `endpoint` + `shutdown` only; deleted `Connection.hx` and stripped Server runloop/SysServer dead code. Updated platform clients/servers and duplex wrappers so nothing implements or exposes the old `Connection` / `connected` / instance-`Client` surface (handler wired via inline `pipeTo(..., {end: true})` pending T2 `Session.run`). Verified Node typecheck of new API stub; existing tests still target old API (T4).
- **Reviewer:** Approve with notes. Diff matches T1: public signatures/options correct; `Connection.hx` gone; no `connected` / `OpenPort` / instance-`Client` in `src/`; platforms consistently start handler then resolve dial (do not await pipe); dead SysServer/runloop stripped. Inline `pipeTo` duplication is acceptable pre-T2 (not harmful overreach). Non-blockers deferred: platform `*Connection` duplex names (T10), README/tests still old API (T4/T10). Fix applied: private ctors on `Client` + platform clients so they are not constructible. Node typecheck of new API stub re-confirmed. Safe to commit T1.

---

### T2 — Shared `Session.run`

**Status:** done (reviewer: approve with notes)

**Files:** new `src/tink/tcp/Session.hx` (name flexible); private duplex helpers only as needed

#### Implementor checklist

- [x] `Session.run(...):` call handler, `pipeTo(sink, {end: true})`
- [x] No platform-specific code
- [x] Not part of public docs as a replacement for `Connection`

#### Reviewer checklist

- [x] Pipe uses `{end: true}`
- [x] Suitable for fire-and-forget from client (after dial success) and server accept
- [x] Does not reintroduce a public `Connection` type

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Added `Session.hx` with `run(source, sink, local, peer, app)` — invokes Handler and `pipeTo(sink, {end: true})`, fire-and-forget (`.handle(_ -> {})`). Platform-agnostic; not documented as a Connection replacement. Replaced all inline `pipeTo(..., {end: true})` call sites in clients/servers with `Session.run` so the shared runner is used (intentional overlap with T3–T8 wiring; those tasks still own platform semantics / TLS / Promise behavior). Verified Node typecheck of Session + Client/Server stubs; full travix suite still blocked on T4 test rewrite.
- **Reviewer:** Approve with notes. `Session.run` matches shared-plumbing sketch (`{end: true}`, fire-and-forget via `.handle`); no platform-specific code; no public `Connection` reintroduced (doc marks Session internal). All five clients + five servers call `Session.run`; sole `pipeTo` under `src/tink/tcp` is inside `Session`. Client dial still resolves after starting run (does not await pipe); server accept remains fire-and-forget. Platform wiring is acceptable T2 overlap — T3–T8 still own TLS/Promise/accept semantics; no harmful overreach. Fix applied: private ctor on `Session`. Node typecheck of Session + Client/Server re-confirmed. Safe to commit T2.

---

### T3 — Node.js Client + Server

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/clients/NodeClient.hx`, `src/tink/tcp/servers/NodeServer.hx`, `src/tink/tcp/connections/NodeConnection.hx` (rename/privatize as needed)

#### Implementor checklist

- [x] Server: listen success → `Server`; each accept → `Session.run(app)`; `shutdown()` shuts listen socket
- [x] Client: dial success → start `Session.run` → resolve `Noise`; dial failure → reject; handler never runs on failure
- [x] TLS options still applied
- [x] Remove all `connected` / old `Client` interface usage

#### Reviewer checklist

- [x] Connect Promise does **not** wait for pipe completion
- [x] Connect failure rejects before handler
- [x] No old-API types left in Node layer

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Audited Node layer against T3 (core dial/accept/`Session.run`/TLS wiring already landed in T1–T2). Confirmed: bind listen → `Server`; accept/`secureConnection` → `Session.run`; `shutdown()` closes listen socket; dial success starts `Session.run` then resolves `Noise` (does not await pipe); dial `error` rejects without running handler; TLS opts still mapped on client/server. Privatized duplex: `NodeConnection` private ctor + `@:allow` for NodeClient/NodeServer; private `NodeServer` ctor; marked duplex as internal (not old `Connection`). Fixed `js.Error` → `js.lib.Error` in shutdown. Node typecheck of API stub + NodeClient/NodeServer/NodeConnection OK. Full `travix node` still blocked on T4 test rewrite. Intentional deferrals for reviewer: duplex type still named `NodeConnection` (T10 rename/purge); other platforms (T5–T8); tests/README (T4/T10).
- **Reviewer:** Approve with notes. Node Client/Server meet T3: dial success → `Session.run` then resolve `Noise` (does not await pipe); `finish`/`done` ensures dial `error` rejects without handler; bind resolves on listen with accept/`secureConnection` → `Session.run`; `shutdown()` closes listen socket; TLS opts mapped on both sides; no `connected` / old instance-`Client` / public `Connection` in Node layer. Not incomplete or overreaching — semantics from T1–T2; T3 delta is privatization + `js.lib.Error`. Fix applied: `NodeConnection` fields made private (ctor already private; `@:allow` retained). Non-blockers deferred: type still named `NodeConnection` (T10); tests/README old API (T4/T10); other platforms (T5–T8). Node API stub typecheck re-confirmed. Safe to commit T3.

---

### T4 — Rewrite core tests (new API only)

**Status:** done (reviewer: approve with notes)

**Files:** `tests/EchoTest.hx`, `tests/TestConnect.hx`, `tests/RunTests.hx`; **delete** `tests/TestAccept.hx` (old API)

#### Implementor checklist

- [x] Tests use only Handler API (`bind`/`connect` with `app`; inbound via `source`; outbound via returned `IdealSource`)
- [x] Assert connect Promise on dial outcome where relevant; session I/O asserted via streams, not connect Promise lifetime
- [x] Use `server.endpoint` / `server.shutdown()`
- [x] `lix run travix node` green (non-TLS)
- [x] No `#if` client construction; no `cnx.sink` / `connected`

#### Reviewer checklist

- [x] No references to removed APIs
- [x] Echo parallel/sequential still valid under new semantics
- [x] TestAccept gone (not `#if false`)

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Rewrote `EchoTest` / `TestConnect` on Handler API only: `Server.bind(to, app)` + `Client.connect(to, app)`; inbound via `source`, outbound via returned `IdealSource`; `server.endpoint` / `server.shutdown()`. Echo sequential/parallel keep the same length expectations (session I/O via streams; connect Promise is dial-only). Added `connectFailure` asserting dial reject without running handler. Deleted `tests/TestAccept.hx`. Excluded `TlsTest` from `RunTests` until T9 (still old API — intentional deferral). Verification: Node suite green (6/6) via travix-equivalent `haxe … tests.hxml` + `node bin/node/tests.js`, and `neko …/travix/run.n node` (exit 0). Note: `lix run travix node` fails in this env (`haxelib` shim broken / SyntaxHub not resolved under `haxelib run-dir`); same build+run path that travix uses is green. Intentional overlap for reviewer: `TlsTest.hx` / `NodeTestNative.hx` still old API (T9/T10); README still old (T10).
- **Reviewer:** Approve with notes. Active suite (`EchoTest`, `TestConnect`, `RunTests`) uses Handler-only `bind`/`connect`, `server.endpoint`/`shutdown`, dial-vs-stream assertions (`connect` + `got` trigger; `connectFailure` rejects without handler). Echo sequential/parallel keep prior length expectations and pass under dial-only connect. `TestAccept.hx` deleted (not `#if false`). `TlsTest` exclusion + leftover old API in `TlsTest.hx` / `#if false` `NodeTestNative.hx` justified for T9/T10. No code fixes required. Re-verified Node 6/6 via `neko …/travix/run.n node` (`lix run travix node` still broken on haxelib shim in this env). Safe to commit T4.

---

### T5 — JVM Client + Server

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/clients/JavaClient.hx`, `src/tink/tcp/servers/JavaServer.hx`, Java connection wrappers

#### Implementor checklist

- [x] Same dial/session semantics as Node; TLS intact
- [x] `lix run travix jvm` green

#### Reviewer checklist

- [x] Connect Promise = dial only
- [x] `Server.shutdown` clean; accept loop intact
- [x] No old-API leftovers

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Audited JVM layer against T5 (core dial/accept/`Session.run`/TLS wiring already landed in T1–T2). Confirmed: bind → `Server` with accept loop → `Session.run`; dial success starts `Session.run` then resolves `Noise` (does not await pipe); dial/`CompletionHandler.failed` rejects without handler; TLS client handshake failure rejects without handler; server TLS handshake failure closes socket and continues accept. Hardened to match T3: private duplex ctors + package `@:allow` on `JavaConnection`/`JavaTlsConnection`; private `JavaServer` ctor; dial Promise uses Node-style `done`/`finish` guard; `shutdown()` close while accept pending ignores `AsynchronousCloseException`. Accept path routed through `onAccepted` + `@:access` so the private `AcceptedHandler` stays encapsulated. Verification: JVM suite green (6/6) via travix-equivalent `neko …/travix/run.n jvm` (`lix run travix jvm` still broken on haxelib shim in this env, same as T4). Intentional deferrals for reviewer: duplex types still named `*Connection` (T10); `TlsTest`/README still old API (T9/T10); accept non-close errors still TODO-log only.

- **Reviewer:** Approve with notes. JVM Client/Server meet T5: dial success → `Session.run` then resolve `Noise` (does not await pipe); `done`/`finish` rejects dial/`CompletionHandler.failed` and TLS handshake failures without running handler; bind → accept/`onAccepted` → `Session.run`; TLS opts still applied client/server; duplex + `JavaServer` privatized like Node T3; no `connected` / old instance-`Client` / public `Connection` in JVM layer. Fix applied: `acceptNext()` swallows synchronous `ClosedChannelException` when re-arming after shutdown (e.g. TLS handshake completing post-close); `failed` ignores `ClosedChannelException` (covers `AsynchronousCloseException`). Non-blockers deferred: duplex still named `*Connection` (T10); `TlsTest`/README old API (T9/T10); non-close accept errors still TODO. Re-verified JVM 6/6 via `neko …/travix/run.n jvm`. Safe to commit T5.

---

### T6 — Eval Client + Server

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/clients/EvalClient.hx`, `src/tink/tcp/servers/EvalServer.hx`

#### Implementor checklist

- [x] Session wiring; honor `BindOptions.loop`
- [x] Connect Promise = dial only
- [x] `lix run travix interp` green

#### Reviewer checklist

- [x] Loop keep-alive / shutdown preserved
- [x] No old-API leftovers

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Audited Eval layer against T6 (core dial/accept/`Session.run`/`BindOptions.loop` already landed in T1–T2). Hardened to match Node T3 / JVM T5: private duplex ctors + package `@:allow` on `EvalConnection`/`EvalTlsConnection`; private `EvalServer` ctor; dial Promise uses Node-style `done`/`finish` guard + cancel closes TCP; dial success → `Session.run` then resolve `Noise` (does not await pipe); accept → `Session.run`; TLS handshake failure rejects/closes without handler. Updated `EvalLoop` NativeEventLoop adapter for current Haxe `run(maxBlock)`/`wake()` (async doorbell + deadline timer, mirroring `hl.uv.Loop` LoopWrapper) so loop keep-alive/shutdown still works under EventLoop. Gated Eval TLS compile paths behind `-D eval_tls` (plain interp rejects `options.tls` with a clear error) because stock mbedtls eval bindings still lack `own_cert`/`set_bio`/ALPN — same deferral README already documents for T9. Verification: interp suite green (6/6) via travix-equivalent `neko …/travix/run.n interp` (`lix run travix interp` still broken on haxelib shim in this env, same as T4/T5). Intentional deferrals for reviewer: duplex types still named `*Connection` (T10); `TlsTest`/README still old API (T9/T10); full Eval TLS needs Haxe with eval_tls mbedtls APIs (T9).

- **Reviewer:** Approve with notes. Eval Client/Server meet T6: dial success → `Session.run` then resolve `Noise` (does not await pipe); `done`/`finish` + cancel closes TCP without running handler on failure; bind honors `BindOptions.loop` / `EvalLoop.current()`; accept → `Session.run`; duplex + `EvalServer` privatized like Node/JVM; plain interp rejects `options.tls` with a clear error; `EvalLoop` `LuvLoopWrapper` matches Haxe `NativeEventLoop` (`run(maxBlock)` / `wake` / `close` / `isAlive`) and HL’s LoopWrapper. Fixes applied: dial cancel no longer double-closes (close inside `finish`; early return on Ok if already cancelled); `EvalTlsConnection` gated behind `-D eval_tls`; `EvalLoop` closes async wake handle if timer init fails. Non-blockers deferred: duplex still named `*Connection` (T10); `TlsTest`/README old API (T9/T10); full Eval TLS needs eval_tls mbedtls APIs (T9); non-close accept errors still TODO. Re-verified interp 6/6 via `neko …/travix/run.n interp`. Safe to commit T6.

---

### T7 — HashLink Client + Server

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/clients/HlClient.hx`, `src/tink/tcp/servers/HlServer.hx`

#### Implementor checklist

- [x] Same semantics; honor HL loop option
- [x] Run HL tests if env allows; note skip in log otherwise

#### Reviewer checklist

- [x] Connect Promise = dial only; UV shutdown path still used via pipe `{end: true}`
- [x] No old-API leftovers

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Audited HL layer against T7 (core dial/accept/`Session.run`/`BindOptions.loop` already landed in T1–T2). Hardened to match Node T3 / JVM T5 / Eval T6: private duplex ctors + package `@:allow` on `HlConnection`/`HlTlsConnection`; private `HlServer` ctor; dial Promise uses Node-style `done`/`finish` guard + cancel closes TCP; dial success → `Session.run` then resolve `Noise` (does not await pipe); dial/TLS handshake failure rejects without handler; accept → `Session.run`; TLS handshake failure closes peer and keeps listening; bind honors `BindOptions.loop` / `HlLoop.current()`; accept errors after `shutdown()` documented as expected (TODO for other accept errors). Verification: HL bytecode compile green via travix-equivalent `haxe -hl bin/hl/tests.hl -lib travix -lib tink_tcp tests.hxml` (exit 0). **Runtime skip:** `hl bin/hl/tests.hl` fails immediately with `Invalid type` — env has Haxe 5.0.0-preview.1 producing HL bytecode that the installed JIT `hl` 1.12.0 (x86_64/Rosetta) cannot load (even a one-line Hello fails the same way). Homebrew HashLink 1.15 is libs-only (no JIT `hl` binary). Arm64 `tink_tcp.hdll` rebuilds fine against Homebrew HL+libuv; x86_64 JIT path lacks a matching libuv. Intentional deferrals for reviewer: duplex types still named `*Connection` (T10); `TlsTest`/README still old API (T9/T10); non-close accept errors still TODO; full HL suite needs a Haxe/HL version pair that can actually run bytecode.
- **Reviewer:** Approve with notes. HL Client/Server meet T7: dial success → `Session.run` then resolve `Noise` (does not await pipe); `done`/`finish` + cancel closes TCP without running handler on failure; bind honors `BindOptions.loop` / `HlLoop.current()`; accept → `Session.run`; TLS opts still applied client/server (handshake failure rejects/closes without handler); duplex + `HlServer` privatized like Node/JVM/Eval; no `connected` / old instance-`Client` / public `Connection` in HL layer. UV shutdown path intact: `Session.run` pipes with `{end: true}` → `HlUvStream.end` → `UvExtras.shutdown`. Re-verified HL bytecode compile green (`haxe -hl … tests.hxml`, exit 0). **Runtime still blocked (not a T7 code defect):** `hl` 1.12.0 cannot load Haxe 5.0.0-preview.1 bytecode (`Invalid type` on suite and on a one-line Hello); Homebrew HashLink 1.15 is libs-only (no `hl` JIT). Acceptable to approve for commit on compile + static review (same bar as noting env skips elsewhere). No code fixes required. Non-blockers deferred: duplex still named `*Connection` (T10); `TlsTest`/README old API (T9/T10); non-close accept errors still TODO. Safe to commit T7.

---

### T8 — C++ Client + Server

**Status:** done (reviewer: approve with notes)

**Files:** `src/tink/tcp/clients/CppClient.hx`, `src/tink/tcp/servers/CppServer.hx`

#### Implementor checklist

- [x] Same semantics; TLS as today (ALPN unchanged)
- [x] `travix cpp` if env ready; else note skip

#### Reviewer checklist

- [x] Connect Promise = dial only
- [x] No old-API leftovers; no DNS-scope creep

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Audited C++ layer against T8 (core dial/accept/`Session.run`/TLS wiring already landed in T1–T2). Hardened to match Node T3 / JVM T5 / Eval T6 / HL T7: private duplex ctors + package `@:allow` on `CppConnection`/`CppTlsConnection`; private `CppServer` ctor; dial Promise uses Node-style `done`/`finish` guard on `ConnectCtx` + cancel closes TCP; dial success → `Session.run` then resolve `Noise` (does not await pipe); dial/TLS handshake failure rejects without handler; accept → `Session.run`; TLS handshake failure closes peer and keeps listening; accept errors after `shutdown()` documented as expected (TODO for other accept errors). TLS opts still applied as before (ALPN unchanged — still not wired on cpp; sync `sys.net.Host` DNS unchanged — intentional, no DNS-scope creep). Verification: `neko …/travix/run.n cpp` fails before compiling tink_tcp sources — `linc_uv` `LoopWrapper.run()` still has the pre–Haxe-5 signature (`() -> Void`) while Haxe 5.0.0-preview.1 `NativeEventLoop` requires `run(maxBlock:Float)` (and typically `wake()`), same class of adapter fix Eval applied in-repo for T6. **Runtime/compile skip:** full cpp suite blocked on updating sibling `linc_uv` EventLoop adapter (outside this repo). Intentional deferrals for reviewer: duplex types still named `*Connection` (T10); `TlsTest`/README still old API (T9/T10); cpp async DNS / ALPN remain README TODOs (out of T8 scope); `linc_uv` LoopWrapper for Haxe 5.
- **Reviewer:** Approve with notes. C++ Client/Server meet T8: dial success → `Session.run` then resolve `Noise` (does not await pipe); `done`/`finish` on `ConnectCtx` + cancel closes TCP without running handler on failure; bind → accept → `Session.run`; TLS opts still applied (handshake failure rejects/closes without handler; ALPN still not wired — README TODO, unchanged); duplex + `CppServer` privatized like Node/JVM/Eval/HL; no `connected` / old instance-`Client` / public `Connection` in C++ layer; no async-DNS creep. Re-confirmed stock `neko …/travix/run.n cpp` fails in sibling `linc_uv` `LoopWrapper` (`() -> Void` vs Haxe 5 `run(maxBlock:Float)`) before any tink_tcp source. **Review-only probe (reverted):** a minimal temporary `linc_uv` stub (`run(maxBlock)` + empty `wake`) unlocked full cpp compile + suite **6/6 green** — confirms tink_tcp C++ layer is sound; a proper Haxe-5 adapter (wake/deadline timer like Eval `LuvLoopWrapper` / HL LoopWrapper) still belongs in `linc_uv`, not this repo. No tink_tcp code fixes required. Non-blockers deferred: duplex still named `*Connection` (T10); `TlsTest`/README old API (T9/T10); cpp async DNS / ALPN; `linc_uv` LoopWrapper. Safe to commit T8.

---

### T9 — TLS tests

**Status:** done (reviewer: approve with notes)

**Files:** `tests/TlsTest.hx`

#### Implementor checklist

- [x] Full rewrite on Handler + `options.tls`
- [x] Green on node/jvm (and eval+`eval_tls` if applicable)

#### Reviewer checklist

- [x] No old Connection/sink API
- [x] TLS options still exercised

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Rewrote `TlsTest` on Handler API only: `Server.bind(to, app, {tls})` + `Client.connect(to, app, {tls})`; inbound via `source`, outbound via returned `IdealSource`; dial-only connect Promise with session I/O via `got` trigger (same pattern as T4 `TestConnect`); `server.endpoint.port` / `server.shutdown()`. Dropped constructible platform `Client`s, `connected`, and `cnx.sink`. Re-enabled `TlsTest` in `RunTests` behind `#if (nodejs || java || hl || cpp || (eval && eval_tls))`. Verification: node 7/7 and jvm 7/7 green via `neko …/travix/run.n {node,jvm}` (`TlsTest` OK). Plain interp 6/6 (TlsTest correctly excluded without `-D eval_tls`). HL bytecode compile green (`haxe -hl … tests.hxml`); runtime still blocked (Haxe 5 / hl 1.12 mismatch from T7). **eval_tls blocked:** stock mbedtls eval bindings lack `alpn_protocols` / `WANT_READ` / etc. — `interp -D eval_tls` fails to compile (same T6 deferral; needs updated Haxe). cpp suite still blocked on sibling `linc_uv` LoopWrapper (T8). Intentional overlap for reviewer: README still old API / `#if false` `NodeTestNative` (T10); duplex still named `*Connection` (T10).
- **Reviewer:** Approve with notes. `TlsTest` is Handler-only: `Server.bind`/`Client.connect` with `options.tls` (server `cert`/`key`, client `ca`/`servername`); inbound via `source`, outbound via returned `IdealSource`; dial-only connect + `got` stream assert matches T4; `server.endpoint.port` / `server.shutdown()`. No constructible clients, `connected`, or `cnx.sink`. Platform gate in `RunTests` matches `TlsTest` `#if`. Re-verified node 7/7 (`neko travix.n node`) and jvm 7/7 (`neko …/travix/run.n jvm`); plain interp 6/6 (TlsTest excluded); HL bytecode compile green. No code fixes required. Non-blockers deferred: eval_tls compile (T6/Haxe mbedtls), HL runtime (T7), cpp/`linc_uv` (T8), README/`NodeTestNative`/`*Connection` names (T10). Safe to commit T9.

---

### T10 — Docs and final purge

**Status:** done (reviewer: approve with notes)

**Files:** `README.md`, `ROADMAP.md`, any remaining `*Connection*` public names, dead comments, disabled tests

#### Implementor checklist

- [x] README documents only Handler API + TLS; static `Client.connect` / `Server.bind`
- [x] Grep purge: `connected`, `RealSink` on TCP public API, `implements Client`, `OpenPort`, old README Client construction
- [x] Platform duplex types private/renamed so they are not the old public `Connection` contract
- [x] ROADMAP goal section reflects final API; residual TODOs only (DNS, ALPN, etc.)

#### Reviewer checklist

- [x] Repo-wide: no traces of previous public API
- [x] Docs match implemented signatures (especially connect Promise = dial)
- [x] CI targets green

#### Agent log

<!-- implementor / reviewer append below -->

- **Implementor:** Rewrote `README.md` for Handler-only API: static `Client.connect` / `Server.bind`, `IncomingConnection`/`Handler`, dial-only connect Promise semantics, TLS via `options.tls` (no constructible platform clients, no `Connection`/`connected`/`cnx.sink`). Renamed platform duplex types `*Connection` → `*Duplex` (`NodeDuplex`, `JavaDuplex`/`JavaTlsDuplex`, `EvalDuplex`/`EvalTlsDuplex`, `HlDuplex`/`HlTlsDuplex`, `CppDuplex`/`CppTlsDuplex`) — still private ctor + `@:allow`, package `tink.tcp.connections`. Deleted dead `#if false` `tests/NodeTestNative.hx`. Softened `TlsTest` comment that named old API. Grep purge clean outside ROADMAP history: no `connected`/`OpenPort`/`implements Client`/old Client construction in src/tests/README; `RealSink` remains only on internal duplex + `Session.run` (not public TCP API). Goal section already matched final API; README TODOs only residual cpp DNS/ALPN. Verification: node **7/7** and jvm **7/7** via `neko …/travix/run.n {node,jvm}` (`lix run travix` still broken on haxelib shim). Env blockers unchanged for reviewer: HL runtime Haxe5/hl mismatch; cpp/`linc_uv` LoopWrapper; eval_tls mbedtls APIs.
- **Reviewer:** Approve with notes. T10 complete: README matches Handler-only static `Client.connect` / `Server.bind` and dial-only connect Promise; no old public API in `src/`/`tests`/README (`connected`/`OpenPort`/`implements Client`/constructible clients/`cnx.sink` gone); `NodeTestNative.hx` deleted; duplex types renamed `*Duplex` and package remains internal. Fix applied: duplex fields + ctors made actually `private` (with existing `@:allow`) — rename alone left them public despite T10 “private/renamed”. Re-verified node **7/7**, jvm **7/7**, interp **6/6**. Non-blockers (env): HL runtime, cpp/`linc_uv`, eval_tls — unchanged. No unfinished ROADMAP chunks remain; overhaul marked complete. Safe to commit T10.
