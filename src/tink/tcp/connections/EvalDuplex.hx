#if eval
package tink.tcp.connections;

import eval.luv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.luv.WrappedStream;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class EvalDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;

  private function new(name:String, native:Tcp) {
    peer = switch native.getPeerName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
    local = switch native.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
    final io = new WrappedStream(name, native);
    source = DuplexSource.wrap('Incoming stream of $name', io);
    sink = DuplexSink.wrap('Outcoming stream of $name', io);
  }
}
#end
