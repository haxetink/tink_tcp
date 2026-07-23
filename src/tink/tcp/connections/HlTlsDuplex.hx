#if hl
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.hl.HlTlsSession;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class HlTlsDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;
  private final session:HlTlsSession;
  private var aborted = false;

  private function new(name:String, session:HlTlsSession, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    this.session = session;
    source = TlsSource.wrap('Incoming stream of $name', session);
    sink = TlsSink.wrap('Outcoming stream of $name', session);
  }

  /** Best-effort hard-close via session force-abort (no TLS close_notify / UV shutdown). */
  private function abort():Void {
    if (aborted)
      return;
    aborted = true;
    session.abort();
  }
}
#end
