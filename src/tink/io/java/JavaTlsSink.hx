#if java
package tink.io.java;

import tink.streams.Stream;
import tink.Chunk;
import tink.io.Sink;

using tink.io.PipeResult;
using tink.CoreApi;

@:allow(tink.io.java)
class JavaTlsSink extends SinkBase<Error, Noise> {
  final session:JavaTlsSession;

  function new(session:JavaTlsSession) {
    this.session = session;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, Error, Noise>> {
    final ret = source.forEach(c -> Future.irreversible((cb:Callback<Handled<Error>>) -> {
      session.write(c, o -> OnMainThread.run(() -> cb.invoke(switch o {
        case Success(_): Resume;
        case Failure(e): Clog(e);
      })));
    }));

    if (options.end)
      ret.handle(_ -> session.shutdown(_ -> {}));

    return ret.map(c -> c.toResult(Noise));
  }

  static public inline function wrap(name:String, session:JavaTlsSession, channel:java.nio.channels.AsynchronousSocketChannel)
    return new JavaTlsSink(session);
}
#end