package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.tcp.internal.TcpSession;
import tink.tcp.internal.DuplexSink;
import tink.tcp.internal.DuplexSource;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class TcpConnection implements Connection {
  private final session:TcpSession;
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  private function new(name:String, session:TcpSession) {
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
