# Tink TCP

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haxetink/public)

This library offers a cross platform TCP API, that is based on tink_io's pure asynchronous streams.

```haxe
package tink.tcp;

using tink.io.Source;//defines IdealSource and RealSource

abstract Endpoint from { host: String, port: Int, ?secure:Bool } {
  public var host(get, never):String;
  public var port(get, never):Int;
  public var secure(get, never):Bool;
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

Construct clients explicitly at the call site:

```haxe
#if java
  final client = new tink.tcp.clients.JavaClient();
#elseif eval
  final client = new tink.tcp.clients.EvalClient();
#else
  final client = new tink.tcp.clients.NodeClient();
#end

client.connect({ host: 'example.com', port: 80 }).handle(o -> switch o {
  case Success(cnx): /* use cnx.source and cnx.sink */;
  case Failure(e): /* handle error */;
});
```

Notes:

- Node.js supports TLS when `endpoint.secure` is true (or port is 443).
- JVM supports TCP only; `connect()` rejects secure endpoints with an error.
- Eval (interp) uses `eval.luv` via libuv. TCP only (no TLS). Hostnames are resolved with getaddrinfo. Optional `?loop` on bind/connect constructors defaults to `sys.thread.Thread.current().events`. Use `EvalLoop.runWithPump` to drive the event loop while running async I/O.
