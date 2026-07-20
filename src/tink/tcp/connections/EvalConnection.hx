#if eval
package tink.tcp.connections;

import eval.luv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.io.luv.WrappedStream;

/** Internal Eval duplex (source/sink/endpoints). Not the old public Connection API. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class EvalConnection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;

  function new(name:String, native:Tcp) {
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
