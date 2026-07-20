package tink.tcp.connections;

#if nodejs
import tink.io.Source;
import tink.io.Sink;

/** Internal duplex plumbing for Session.run. */
@:allow(tink.tcp.clients.NodeClient)
@:allow(tink.tcp.servers.NodeServer)
class NodeDuplex {
  private final source:RealSource;
  private final sink:RealSink;
  private final local:Endpoint;
  private final peer:Endpoint;

  private function new(name:String, native:js.node.net.Socket) {
    local = {host: native.localAddress, port: native.localPort};
    peer = {host: native.remoteAddress, port: native.remotePort};
    source = Source.ofNodeStream('Incoming stream of $name', native);
    sink = Sink.ofNodeStream('Outcoming stream of $name', native);
  }
}
#end
