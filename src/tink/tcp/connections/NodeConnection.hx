package tink.tcp.connections;

#if nodejs
import tink.tcp.Connection;
import tink.io.Source;
import tink.io.Sink;

class NodeConnection implements Connection {
	public final source:RealSource;
	public final sink:RealSink;
	public final local:Endpoint;
	public final peer:Endpoint;
	
	public function new(name:String, native:js.node.net.Socket) {
		local = { host: native.localAddress, port: native.localPort };
		peer = { host: native.remoteAddress, port: native.remotePort };
		source = Source.ofNodeStream('Incoming stream of $name', native);
		sink = Sink.ofNodeStream('Outcoming stream of $name', native);
	}
}
#end