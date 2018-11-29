package;

import tink.tcp.*;
import tink.tcp.uv.*;
import tink.streams.Stream;
import tink.Chunk;

using tink.io.Source;
using tink.CoreApi;

class Playground {
	static function main() {
		UvAcceptor.inst.bind(7001).handle(function(o) switch o {
			case Success(open):
				open.setHandler(function(incoming:Incoming):Future<Outgoing> {
					trace('from: ' + incoming.from.host.toString() + ':' + incoming.from.port);
					trace('to: ' + incoming.to.host.toString() + ':' + incoming.to.port);
					return Future.sync({
						stream: incoming.stream.idealize(function(_) return Source.EMPTY),
						allowHalfOpen: true,
					});
				});
			case Failure(e):
				trace(e);
		});
	}
}