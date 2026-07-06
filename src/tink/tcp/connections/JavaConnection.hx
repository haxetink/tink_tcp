package tink.tcp.connections;

#if java
import tink.tcp.Connection;
import tink.io.Source;
import tink.io.Sink;

class JavaConnection implements Connection {
	public final source:RealSource;
	public final sink:RealSink;
	public final local:Endpoint;
	public final peer:Endpoint;
	
	public function new(name:String, native:java.nio.channels.AsynchronousSocketChannel) {
		local = native.getLocalAddress();
		peer = native.getRemoteAddress();
		source = Source.ofJavaSocketChannel('Incoming stream of $name', native);
		sink = Sink.ofJavaSocketChannel('Outcoming stream of $name', native);
	}
}
#end
