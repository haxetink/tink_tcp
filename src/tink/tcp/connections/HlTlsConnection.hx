#if hl
package tink.tcp.connections;

import tink.tcp.Connection;
import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.hl.HlTlsSession;

class HlTlsConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, session:HlTlsSession, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    source = TlsSource.wrap('Incoming stream of $name', session);
    sink = TlsSink.wrap('Outcoming stream of $name', session);
  }
}
#end
