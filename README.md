# Tink TCP

This library offers a cross platform TCP API, that is based on tink_io's asynchronous streams. Currently it works only for nodejs and neko, but the current state shows that it can be implemented on any platform that exposes TCP capabilities.

The API is very lean:

```haxe
package tink.tcp;

class Connection {
	public var source(default, null):Source;
	public var sink(default, null):Sink;
	public var name(default, null):String;
  static public function tryEstablish(endpoint
}

abstract Endpoint from { host: String, port: Int } {
  public var host(get, never):String;
  public var port(get, never):Int;
  @:from static function fromPort(port:Int):Endpoint;
  @:to function toString():String;
}


```