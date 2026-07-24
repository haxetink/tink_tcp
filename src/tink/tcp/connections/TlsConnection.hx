package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSession;
import tink.io.DuplexSink;
import tink.io.DuplexSource;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class TlsConnection implements Connection {
  private final session:TlsSession;
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  private function new(name:String, session:TlsSession) {
    this.session = session;
    this.local = session.getLocalEndpoint();
    this.peer = session.getPeerEndpoint();
    source = DuplexSource.wrap('Incoming stream of $name', session);
    sink = DuplexSink.wrap('Outcoming stream of $name', session);
  }

  public function abort():Void {
    session.abort();
  }
}
