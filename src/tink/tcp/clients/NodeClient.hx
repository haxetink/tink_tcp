package tink.tcp.clients;

#if nodejs
import tink.tcp.Client;
import tink.tcp.Connection;
import tink.tcp.connections.NodeConnection;

using tink.CoreApi;

class NodeClient implements Client {
	public function new() {}
	public function connect(to:Endpoint):Promise<Connection> {
		return new Promise((resolve, reject) -> {
			var done = false;
			function finish(f:Void->Void) {
				if (!done) {
					done = true;
					f();
				}
			}
			final native = to.secure ? js.node.Tls.connect(to.port, to.host) : js.node.Net.connect(to.port, to.host);
			native.once('connect', () -> finish(() -> resolve((new NodeConnection('Connection to $to', native):Connection))));
			native.once('error', e -> finish(() -> reject(Error.ofJsError(e))));
			return function() {
				if (!done) {
					done = true;
					native.destroy();
				}
			};
		});
	}
}
#end
