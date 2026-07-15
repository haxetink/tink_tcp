#if cpp
package tink.tcp.connections;

import tink.tcp.Connection;
import tink.io.Source;
import tink.io.Sink;
import tink.io.cpp.CppTlsSession;
import tink.io.cpp.CppTlsSource;
import tink.io.cpp.CppTlsSink;

class CppTlsConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;

  public function new(name:String, session:CppTlsSession, ?local:Endpoint, ?peer:Endpoint) {
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
    source = CppTlsSource.wrap('Incoming stream of $name', session);
    sink = CppTlsSink.wrap('Outcoming stream of $name', session);
  }
}
#end
