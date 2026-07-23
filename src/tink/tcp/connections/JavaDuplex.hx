package tink.tcp.connections;

#if java
import tink.io.Source;
import tink.io.Sink;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients)
@:allow(tink.tcp.servers)
class JavaDuplex implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;
  private final channel:java.nio.channels.AsynchronousSocketChannel;
  var aborted = false;

  private function new(name:String, native:java.nio.channels.AsynchronousSocketChannel) {
    channel = native;
    local = native.getLocalAddress();
    peer = native.getRemoteAddress();
    source = Source.ofJavaSocketChannel('Incoming stream of $name', native);
    sink = Sink.ofJavaSocketChannel('Outcoming stream of $name', native);
  }

  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    try
      channel.close()
    catch (_:Dynamic) {}
  }
}
#end
