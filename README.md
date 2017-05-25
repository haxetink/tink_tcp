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

class OpenPort {
  
  var queued(default, null):Int;
  var running(default, null):Int;
  var maxRunning(default, null):Int = 0x100000;

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
