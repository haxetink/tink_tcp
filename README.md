# Tink TCP

This library offers a cross platform TCP API, that is based on tink_io's asynchronous streams. As of now it works only for nodejs and neko (and quite possibly Java and C++), but the current state shows that it can be implemented on any platform that exposes TCP capabilities in some fashion.

The API is currently very lean:

```haxe
package tink.tcp;

class Connection {
	public var source(default, null):tink.io.Source;
	public var sink(default, null):tink.io.Sink;
	public var name(default, null):String;
  
  static public function tryEstablish(endpoint:Endpoint, ?reader:tink.io.Worker, ?writer:tink.io.Worker):Suprise<Connection, Error>;
  static public function establish(endpoint:Endpoint, ?reader:tink.io.Worker, ?writer:tink.io.Worker):Connection;
}

abstract Endpoint from { host: String, port: Int } {
  public var host(get, never):String;
  public var port(get, never):Int;
  @:from static function fromPort(port:Int):Endpoint;
  @:to function toString():String;
}

abstract Server {
  public var connected(get, never):Signal<Connection>;
  public function close():Void;
  static public function bind(port:Int):Surprise<Server, Error>;
}
```

The difference between the two methods to establish connections is that the latter will simply pretend it is connected and give you errors when you try to read from the source or write to the sink. The main use of tryEstablish is to determine if a connection to some port is possible, without wanting to do any IO. On nodejs, the workers are currently not actually used by the current implementation. Note that for binding ports on neko, java and cpp, this library will require you to add `-lib tink_runloop`. Use `-D concurrent` to use multiple threads.