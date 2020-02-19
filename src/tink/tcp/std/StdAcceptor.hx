package tink.tcp.hl;

import tink.tcp.OpenPort;
import sys.net.*;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;

class StdAcceptor {
	static public var inst(default, null):StdAcceptor = new StdAcceptor();

	function new() {}

	public function bind(port:Int):Promise<OpenPort>
		return Future.async(cb -> {
			var s = new SignalTrigger<Session>();
			tink.tcp.Server.bind(port).handle(o -> switch (o) {
				case Success(server):
					server.connected.handle(cnx -> {
						var closeTrigger = Future.trigger();
						var closed = closeTrigger.asFuture();
						var onClosed = cnx -> {
							closeTrigger.trigger(Noise);
						};
						@:privateAccess cnx.onClose = onClosed;
						s.trigger({
							sink: cast cnx.sink,
							incoming: {
								from: cnx.peer,
								to: {
									host: "127.0.0.1",
									port: port
								},
								stream: cnx.source,
								closed: closed
							},
							destroy: () -> {
								cnx.close();
								return;
							}
						});
					});
				case Failure(e): cb(Failure(e));
			});
			cb(Success(new OpenPort(s, port)));
		});
}
