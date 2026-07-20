#if java
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.java.JavaTlsSession;
import tink.io.java.JavaTlsSource;
import tink.io.java.JavaTlsSink;

/** Internal JVM TLS duplex (source/sink/endpoints). Not the old public Connection API. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class JavaTlsConnection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;

  function new(name:String, session:JavaTlsSession) {
    final native = session.channel;
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = JavaTlsSource.wrap('Incoming stream of $name', session);
    sink = JavaTlsSink.wrap('Outcoming stream of $name', session, native);
  }
}
#end
