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

interface Connection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;
}

interface Client {
  function connect(to:Endpoint):Promise<Connection>;
}

interface ServerObject {
  final connected:Signal<Connection>;
  var port(get, never):Int;
  function close():Promise<Noise>;

  static public function bind(target:Endpoint):Promise<Server>;
}
```

Platform implementations:

- Node.js: `tink.tcp.clients.NodeClient`, `tink.tcp.servers.NodeServer`
- JVM: `tink.tcp.clients.JavaClient`, `tink.tcp.servers.JavaServer`
- Eval (interp): `tink.tcp.clients.EvalClient`, `tink.tcp.servers.EvalServer`, `tink.tcp.eval.EvalLoop`
- HashLink: `tink.tcp.clients.HlClient`, `tink.tcp.servers.HlServer`, `tink.tcp.hl.HlLoop`
- C++ (hxcpp + linc_uv): `tink.tcp.clients.CppClient`, `tink.tcp.servers.CppServer`

Construct clients explicitly at the call site:

```haxe
#if java
  final client = new tink.tcp.clients.JavaClient();
#elseif eval
  final client = new tink.tcp.clients.EvalClient();
#elseif hl
  final client = new tink.tcp.clients.HlClient();
#elseif cpp
  final client = new tink.tcp.clients.CppClient();
#else
  final client = new tink.tcp.clients.NodeClient();
#end

client.connect({ host: 'example.com', port: 80 }).handle(o -> switch o {
  case Success(cnx): /* use cnx.source and cnx.sink */;
  case Failure(e): /* handle error */;
});
```

TLS is opt-in via an explicit `tls` option on `Server.bind` and `Client.connect`. It is implemented on **Node.js**, **JVM**, **HashLink**, **C++** (owned mbedtls over libuv), and **eval** (when built with an Haxe version that exposes eval mbedtls `set_bio`, `own_cert`, and ALPN). PKCS#8 private keys only (`BEGIN PRIVATE KEY`). CI `interp` TLS tests are gated behind `-D eval_tls` until the updated Haxe build is available upstream.

```haxe
// Server: requires cert + key (see TlsServerOptions in tink.tcp.Tls)
Server.bind({ host: '0.0.0.0', port: 443 }, { tls: { cert: certBytes, key: keyBytes } });

// Client: see TlsClientOptions in tink.tcp.Tls
client.connect({ host: 'example.com', port: 443 }, { tls: { ca: caBytes, servername: 'example.com' } });
```

Eval TLS local test run: `lix run travix interp -D eval_tls`

C++ requires `-lib linc_uv` (and hxcpp). Example: `lix run travix cpp`

## TODO

- **cpp DNS:** `CppClient` / `CppServer` currently resolve hostnames synchronously via `sys.net.Host`. Switch to async `uv_getaddrinfo` (`linc_uv` `GetAddrInfo`) so connect/bind do not block the event loop.
- **cpp ALPN:** TLS ALPN options are accepted in the public API but not yet wired on cpp (throws if `alpn` is set).
