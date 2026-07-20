#if cpp
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.TlsSink;
import tink.io.TlsSource;
import tink.io.cpp.CppTlsSession;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class CppTlsDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;

  private function new(name:String, session:CppTlsSession, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    source = TlsSource.wrap('Incoming stream of $name', session);
    sink = TlsSink.wrap('Outcoming stream of $name', session);
  }
}
#end
