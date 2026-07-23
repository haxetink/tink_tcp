#if eval
#if eval_tls
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.eval.EvalTlsSession;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class EvalTlsDuplex implements Connection {
  private final session:EvalTlsSession;
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  private function new(name:String, session:EvalTlsSession) {
    this.session = session;
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

  /** Best-effort hard-close via session-level force-abort (skips TLS close_notify / UV shutdown). */
  public function abort():Void {
    session.abort();
  }
}
#end
#end
