package tink.tcp.connections;

#if java
import tink.io.Source;
import tink.io.Sink;

/** Internal JVM duplex (source/sink/endpoints). Not the old public Connection API. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class JavaConnection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;

  function new(name:String, native:java.nio.channels.AsynchronousSocketChannel) {
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = Source.ofJavaSocketChannel('Incoming stream of $name', native);
    sink = Sink.ofJavaSocketChannel('Outcoming stream of $name', native);
  }
}
#end
