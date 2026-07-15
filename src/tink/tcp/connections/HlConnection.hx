#if hl
package tink.tcp.connections;

import hl.uv.Stream;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.tcp.Connection;
import tink.io.hl.HlUvStream;

class HlConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, native:Stream, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    final io = new HlUvStream(name, native);
    source = DuplexSource.wrap('Incoming stream of $name', io);
    sink = DuplexSink.wrap('Outcoming stream of $name', io);
  }
}
#end
