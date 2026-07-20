package tink.tcp.connections;

#if nodejs
import tink.io.Source;
import tink.io.Sink;

/** Internal Node duplex (source/sink/endpoints). Not the old public Connection API. */
@:allow(tink.tcp.clients.NodeClient)
@:allow(tink.tcp.servers.NodeServer)
class NodeConnection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;

  function new(name:String, native:js.node.net.Socket) {
    local = {host: native.localAddress, port: native.localPort};
    peer = {host: native.remoteAddress, port: native.remotePort};
    source = Source.ofNodeStream('Incoming stream of $name', native);
    sink = Sink.ofNodeStream('Outcoming stream of $name', native);
  }
}
#end
