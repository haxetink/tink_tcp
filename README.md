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
  var connected(get, never):Signal<Connection>;
  var port(get, never):Int;
  function close():Promise<Noise>;
}

abstract Server(ServerObject) from ServerObject {
  static public function bind(port:Int):Promise<Server>;
}
```

Platform implementations:

- Node.js: `tink.tcp.clients.NodeClient`, `tink.tcp.servers.NodeServer`
- JVM: `tink.tcp.clients.JavaClient`, `tink.tcp.servers.JavaServer`

Construct clients explicitly at the call site:

```haxe
#if java
  var client = new tink.tcp.clients.JavaClient();
#else
  var client = new tink.tcp.clients.NodeClient();
#end

client.connect({ host: 'example.com', port: 80 }).handle(function (o) switch o {
  case Success(cnx): /* use cnx.source and cnx.sink */;
  case Failure(e): /* handle error */;
});
```

Notes:

- Node.js supports TLS when `endpoint.secure` is true (or port is 443).
- JVM supports TCP only; `connect()` rejects secure endpoints with an error.
