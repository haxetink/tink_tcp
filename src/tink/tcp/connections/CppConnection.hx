#if cpp
package tink.tcp.connections;

import uv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.cpp.CppUvStream;

class CppConnection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, tcp:Tcp, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? endpointFrom(tcp.getSockAddress());
    this.peer = peer ?? endpointFrom(tcp.getPeerAddress());
    final io = new CppUvStream(name, tcp);
    source = DuplexSource.wrap('Incoming stream of $name', io);
    sink = DuplexSink.wrap('Outcoming stream of $name', io);
  }

  static function endpointFrom(addr:{host:String, port:Int}):Endpoint {
    return {host: addr.host, port: addr.port};
  }
}
#end
