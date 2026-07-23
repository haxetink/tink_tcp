#if cpp
package tink.tcp.connections;

import uv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.cpp.CppUvStream;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class CppDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;
  private final stream:CppUvStream;

  private function new(name:String, tcp:Tcp, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? endpointFrom(tcp.getSockAddress());
    this.peer = peer ?? endpointFrom(tcp.getPeerAddress());
    this.stream = new CppUvStream(name, tcp);
    source = DuplexSource.wrap('Incoming stream of $name', stream);
    sink = DuplexSink.wrap('Outcoming stream of $name', stream);
  }

  private function abort():Void {
    stream.abort();
  }

  static function endpointFrom(addr:{host:String, port:Int}):Endpoint {
    return {host: addr.host, port: addr.port};
  }
}
#end
