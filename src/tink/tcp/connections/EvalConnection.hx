#if eval
package tink.tcp.connections;

import eval.luv.Tcp;
import tink.io.Source;
import tink.io.Sink;
import tink.io.DuplexSink;
import tink.io.DuplexSource;
import tink.tcp.Connection;
import tink.io.luv.WrappedStream;

class EvalConnection implements Connection {
	public final source:RealSource;
	public final sink:RealSink;
	public final local:Endpoint;
	public final peer:Endpoint;

	public function new(name:String, native:Tcp) {
		peer = switch native.getPeerName() {
			case Ok(addr): (addr : Endpoint);
			case Error(_): { host: '?', port: 0 };
		};
		local = switch native.getSockName() {
			case Ok(addr): (addr : Endpoint);
			case Error(_): { host: '?', port: 0 };
		};
		final io = new WrappedStream(name, native);
		source = DuplexSource.wrap('Incoming stream of $name', io);
		sink = DuplexSink.wrap('Outcoming stream of $name', io);
	}
}
#end
