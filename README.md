[![Gitter](https://img.shields.io/gitter/room/nwjs/nw.js.svg?maxAge=2592000)](https://gitter.im/haxetink/public)

# Tink TCP

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

typedef Incoming = {
  var from(default, never):Endpoint;
  var to(default, never):Endpoint;
  var stream(default, never):RealSource;
}

typedef Outgoing = {
  var stream(default, never):IdealSource;
  @:optional var allowHalfOpen(default, never):Bool;
}

abstract Handler {
  function handle(incoming:Incoming):Future<Outgoing>;
  @:from static private function ofAsync(f:Incoming->Future<Outgoing>):Handler;
  @:from static private function ofSync(f:Incoming->Outgoing):Handler;
}

interface OpenPort {
  function setHandler(handler:Handler):Promise<Noise>;
  function shutdown(?hard:Bool):Promise<Bool>;
}

interface Connector {
  function connect(to:Endpoint, handler:Handler):Promise<Noise>;
}

interface Acceptor {
  function bind(?port:Int):Promise<OpenPort>;
}
```