#if eval
#if eval_tls
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.eval.EvalTlsSession;

/** Internal Eval TLS duplex (source/sink/endpoints). Not the old public Connection API. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class EvalTlsConnection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;

  function new(name:String, session:EvalTlsSession) {
    final native = session.tcp;
    peer = switch native.getPeerName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
    local = switch native.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
    source = TlsSource.wrap('Incoming stream of $name', session);
    sink = TlsSink.wrap('Outcoming stream of $name', session);
  }
}
#end
#end
