package tink.tcp;

private typedef EndpointData = {
  public final host:String;
  public final port:Int;
}

@:forward(host, port)
abstract Endpoint(EndpointData) from EndpointData {
  public inline function new(host, port) {
    this = {host: host, port: port}
  }
  
  @:from inline static function fromPort(port:Int):Endpoint
    return { port: port, host: '127.0.0.1' };
  
  @:to public inline function toString():String
    return '${this.host}:${this.port}';
    
  #if eval
  @:from static function fromSockAddr(addr:eval.luv.SockAddr):Endpoint {
    final port = addr.port ?? 0;
    final text = addr.toString();
    final host = {
      final idx = text.lastIndexOf(':');
      if (idx >= 0) text.substr(0, idx) else text;
    };
    return { host: host, port: port };
  }
  #end

  #if java
  @:from static inline function fromJavaSocketAddress(address:java.net.SocketAddress):Endpoint {
    final inet:java.net.InetSocketAddress = cast address;
    return {host: inet.getHostName(), port: inet.getPort()}
  }
  @:to inline function toJavaSocketAddress():java.net.SocketAddress {
    return new java.net.InetSocketAddress(this.host, this.port);
  }
  #end
}
