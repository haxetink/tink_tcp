#if cpp
package tink.tcp.connections;

import uv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.tcp.Connection;
import tink.io.cpp.CppUvStream;
import tink.io.cpp.CppUvSource;
import tink.io.cpp.CppUvSink;

class CppConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, tcp:Tcp, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? endpointFrom(tcp.getSockAddress());
    this.peer = peer ?? endpointFrom(tcp.getPeerAddress());
    final io = new CppUvStream(name, tcp);
    source = CppUvSource.wrap('Incoming stream of $name', io);
    sink = CppUvSink.wrap('Outcoming stream of $name', io);
  }

  static function endpointFrom(addr:{host:String, port:Int}):Endpoint {
    return {host: addr.host, port: addr.port};
  }
}
#end
