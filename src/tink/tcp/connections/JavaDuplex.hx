package tink.tcp.connections;

#if java
import tink.io.Source;
import tink.io.Sink;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class JavaDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;

  private function new(name:String, native:java.nio.channels.AsynchronousSocketChannel) {
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = Source.ofJavaSocketChannel('Incoming stream of $name', native);
    sink = Sink.ofJavaSocketChannel('Outcoming stream of $name', native);
  }
}
#end
