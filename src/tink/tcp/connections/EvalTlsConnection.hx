#if eval
package tink.tcp.connections;

import tink.tcp.Connection;
import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.eval.EvalTlsSession;

class EvalTlsConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, session:EvalTlsSession) {
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
