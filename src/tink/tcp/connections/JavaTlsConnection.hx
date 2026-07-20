#if java
package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.io.java.JavaTlsSession;
import tink.io.java.JavaTlsSource;
import tink.io.java.JavaTlsSink;

class JavaTlsConnection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, session:JavaTlsSession) {
    final native = session.channel;
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = JavaTlsSource.wrap('Incoming stream of $name', session);
    sink = JavaTlsSink.wrap('Outcoming stream of $name', session, native);
  }
}
#end
