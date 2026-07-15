package tink.io;

import tink.streams.Stream;
import tink.Chunk;
import tink.io.Sink;

using tink.io.PipeResult;
using tink.CoreApi;

class TlsSink extends SinkBase<Error, Noise> {
  final session:TlsSession;

  function new(session:TlsSession) {
    this.session = session;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, Error, Noise>> {
    final ret = source.forEach(c -> Future.irreversible((cb:Callback<Handled<Error>>) -> {
      session.write(c, o -> cb.invoke(switch o {
        case Success(_): Resume;
        case Failure(e): Clog(e);
      }));
    }));

    if (options.end)
      ret.handle(_ -> session.shutdown(_ -> {}));

    return ret.map(c -> c.toResult(Noise));
  }

  static public inline function wrap(name:String, session:TlsSession)
    return new TlsSink(session);
}
