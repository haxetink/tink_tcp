#if cpp
package tink.tcp.connections;

import uv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.cpp.CppUvStream;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class CppConnection implements Connection {
  private final stream:CppUvStream;
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  private function new(name:String, tcp:Tcp, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? endpointFrom(tcp.getSockAddress());
    this.peer = peer ?? endpointFrom(tcp.getPeerAddress());
    this.stream = new CppUvStream(name, tcp);
    source = DuplexSource.wrap('Incoming stream of $name', stream);
    sink = DuplexSink.wrap('Outcoming stream of $name', stream);
  }

  public function abort():Void {
    stream.abort();
  }

  static function endpointFrom(addr:{host:String, port:Int}):Endpoint {
    return {host: addr.host, port: addr.port};
  }
}
#end
