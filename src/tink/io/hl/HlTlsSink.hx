#if hl
package tink.io.hl;

import tink.streams.Stream;
import tink.Chunk;
import tink.io.Sink;

using tink.io.PipeResult;
using tink.CoreApi;

@:allow(tink.io.hl)
class HlTlsSink extends SinkBase<tink.core.Error, Noise> {
  final session:HlTlsSession;

  function new(session:HlTlsSession) {
    this.session = session;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, tink.core.Error, Noise>> {
    final ret = source.forEach(c -> Future.irreversible((cb:Callback<Handled<tink.core.Error>>) -> {
      session.write(c, o -> cb.invoke(switch o {
        case Success(_): Resume;
        case Failure(e): Clog(e);
      }));
    }));

    if (options.end)
      ret.handle(_ -> session.shutdown(_ -> {}));

    return ret.map(c -> c.toResult(Noise));
  }

  static public inline function wrap(name:String, session:HlTlsSession)
    return new HlTlsSink(session);
}
#end
