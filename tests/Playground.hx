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
				trace('opened');
				open.setHandler(function(incoming:Incoming):Future<Outgoing> {
					trace(incoming);
					incoming.stream.chunked().forEach(function(c:Chunk) {
						trace(c.length);
						return Resume;
					}).handle(function(o) trace(o));
					trace('return');
					return Future.sync({
						stream: Source.EMPTY,
						allowHalfOpen: true,
					});
				});
			case Failure(e):
				trace(e);
		});
	}
}