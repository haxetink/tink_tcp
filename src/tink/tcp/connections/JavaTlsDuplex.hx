#if java
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.java.JavaTlsSession;
import tink.io.java.JavaTlsSource;
import tink.io.java.JavaTlsSink;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class JavaTlsDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;

  private function new(name:String, session:JavaTlsSession) {
    final native = session.channel;
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = JavaTlsSource.wrap('Incoming stream of $name', session);
    sink = JavaTlsSink.wrap('Outcoming stream of $name', session, native);
  }
}
#end
