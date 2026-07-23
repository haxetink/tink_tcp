#if hl
package tink.tcp.connections;

import hl.uv.Stream;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.hl.HlUvStream;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class HlConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;
  private final io:HlUvStream;
  private var aborted = false;

  private function new(name:String, native:Stream, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    io = new HlUvStream(name, native);
    source = DuplexSource.wrap('Incoming stream of $name', io);
    sink = DuplexSink.wrap('Outcoming stream of $name', io);
  }

  /** Best-effort hard-close; skips UV shutdown / stream `end()`. */
  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    io.abort();
  }
}
#end
