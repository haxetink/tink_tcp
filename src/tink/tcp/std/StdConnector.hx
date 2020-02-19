package tink.tcp.std;

// import tink.http.StructuredBody;
using tink.io.Sink;
using tink.io.Source;
using tink.CoreApi;

#if (tink_runloop && tink_http)
class StdConnector {
	static public function connect(to:Endpoint, handler:Handler, ?pool:Array<tink.io.Worker>):Promise<Noise> {
		return Future.async(function(cb) {
			var reader = pool != null ? pool[Std.random(pool.length)] : tink.io.Worker.get();
			var writer = pool != null ? pool[Std.random(pool.length)] : tink.io.Worker.get();
			var sourceClosed = Future.trigger();
			tink.tcp.Connection.tryEstablish(to, reader, writer).handle(function(o) switch o {
				case Success(cnx):
					handler.handle({
						from: to,
						to: cnx.peer,
						stream: cnx.source,
						closed: sourceClosed.map(_ -> {
							return Noise;
						})
					}).handle(function(outgoing) {
						var out = 'Outgoing stream of connection to $to';
						tink.http.Request.IncomingRequest.parse(cnx.peer.host, outgoing.stream).handle(function(r) switch r {
							case Success(req):
								var body:RealSource = switch (req.body) {
									case Plain(bodyStream):
										bodyStream;
									case Parsed(array):
										#if tink_multipart
										var parts = [];
										#end
										array.map(function(namedBodyPart) {
											var out = '';
											switch namedBodyPart.value {
												case Value(val):
													#if tink_multipart
													parts.push(tink.multipart.Part.value(namedBodyPart.name, val));
													#else
													cb(Failure(new Error('Multi-part parsing is not enabled. (must include -lib tink_multipart)')));
													#end
												case File(file):
													#if tink_multipart
													parts.push(tink.multipart.Part.file('datafile', file.fileName, file.mimeType,
														tink.io.Source.RealSourceTools.idealize(file.read(), _ -> tink.Chunk.EMPTY)));
													#else
													cb(Failure(new Error('Multi-part parsing is not enabled. (must include -lib tink_multipart)')));
													#end
											}
											return out;
										}).join("&");
										#if tink_multipart
										(new tink.multipart.Multipart(null, parts).toIdealSource() : RealSource);
										#end
								};
								body.prepend(req.header.toString()).pipeTo(cnx.sink, {end: true}).handle(function(o) {
									trace(o);
									cb(switch o {
										case SinkFailed(e, _): Failure(e);
										case SinkEnded(_, {depleted: true}): Failure(new Error('$out closed before all data could be written'));
										default: Success(Noise);
									});
								});
							case Failure(e):
								cb(Failure(e));
						});
					});
				case Failure(e):
					cb(Failure(e));
			});
		});
	}
}
#end
