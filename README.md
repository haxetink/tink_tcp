# Tink TCP

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haxetink/public)

This library offers a cross platform TCP API, that is based on tink_io's pure asynchronous streams.

```haxe
package tink.tcp;

using tink.io.Source;//defines IdealSource and RealSource

abstract Endpoint from { host: String, port: Int } {
  public var host(get, never):String;
  public var port(get, never):Int;
  @:from static function fromPort(port:Int):Endpoint;
  @:to function toString():String;
}

interface IncomingConnection {
  var source(get, never):RealSource;
  var local(get, never):Endpoint;
  var peer(get, never):Endpoint;
  function abort():Void;
}

typedef Handler = IncomingConnection->IdealSource;

class Client {
  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise>;
}

interface Server {
  var endpoint(get, never):Endpoint;
  function shutdown():Promise<Noise>;

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server>;
}
```

`Client.connect` resolves when the TCP/TLS dial **succeeds** and rejects when it **fails**. The handler runs only after a successful dial. The Promise does **not** wait for the handler’s outbound pipe or session lifetime.

`Server.bind` takes a `Handler` up front. Each accepted peer is passed to that handler; the returned `IdealSource` is piped to the peer (`pipeTo(sink, {end: true})`).

**Graceful close vs `abort()`:** The normal teardown is finishing both sides of the session — drain or end the inbound `source`, and let the returned `IdealSource` complete so `pipeTo(sink, {end: true})` can shut the socket down cleanly (TCP FIN / orderly TLS shutdown as the platform provides). Call `incoming.abort()` when you need to tear down mid-session without completing that path: it is an **idempotent, best-effort hard close / local cleanup** of the underlying socket or handle (pending reads/writes fail or end; graceful stream `end` / TLS `close_notify` are skipped). A TCP RST (or `ECONNRESET`) is **not** promised.

Use the static entry points — do not construct platform clients:

```haxe
Server.bind({ host: '0.0.0.0', port: 8080 }, incoming -> {
  // read from incoming.source; return bytes to send
  return ('hello\n' : IdealSource).append(incoming.source.idealize(_ -> Source.EMPTY));
}).handle(o -> switch o {
  case Success(server):
    Client.connect(server.endpoint, incoming -> {
      incoming.source.all().handle(_ -> {});
      return ('ping\n' : IdealSource);
    }).handle(o -> switch o {
      case Success(_): /* dial ok; session I/O is via streams */
      case Failure(e): /* dial failed */
    });
  case Failure(e): /* bind failed */
});
```

Platform backends (dispatched by `Client.connect` / `Server.bind`):

- Node.js
- JVM
- Eval (interp), with optional `BindOptions.loop`
- HashLink, with optional `BindOptions.loop`
- C++ (hxcpp + linc_uv)

TLS is opt-in via `options.tls` on `Server.bind` and `Client.connect`. It is implemented on **Node.js**, **JVM**, **HashLink**, **C++** (owned mbedtls over libuv), and **eval** (when built with an Haxe version that exposes eval mbedtls `set_bio`, `own_cert`, and ALPN). PKCS#8 private keys only (`BEGIN PRIVATE KEY`). CI `interp` TLS tests are gated behind `-D eval_tls` until the updated Haxe build is available upstream.

```haxe
// Server: requires cert + key (see TlsServerOptions in tink.tcp.Tls)
Server.bind({ host: '0.0.0.0', port: 443 }, incoming -> {
  incoming.source.all().handle(_ -> {});
  return ('ok' : IdealSource);
}, { tls: { cert: certBytes, key: keyBytes } });

// Client: see TlsClientOptions in tink.tcp.Tls
Client.connect({ host: 'example.com', port: 443 }, incoming -> {
  incoming.source.all().handle(_ -> {});
  return Source.EMPTY;
}, { tls: { ca: caBytes, servername: 'example.com' } });
```

Eval TLS local test run: `lix run travix interp -D eval_tls`

C++ requires `-lib linc_uv` (and hxcpp). Example: `lix run travix cpp`

## TODO

- **cpp DNS:** `CppClient` / `CppServer` currently resolve hostnames synchronously via `sys.net.Host`. Switch to async `uv_getaddrinfo` (`linc_uv` `GetAddrInfo`) so connect/bind do not block the event loop.
- **cpp ALPN:** TLS ALPN options are accepted in the public API but not yet wired on cpp (throws if `alpn` is set).
