#if java
package tink.io.java;

import tink.streams.Stream;
import tink.Chunk;
import tink.io.Sink;

using tink.io.PipeResult;
using tink.io.Source;
using tink.CoreApi;

@:allow(tink.io.java)
class JavaTlsSink extends SinkBase<Error, Noise> {
  final session:JavaTlsSession;

  function new(session:JavaTlsSession) {
    this.session = session;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, Error, Noise>> {
    final body = source.forEach(c -> Future.irreversible((cb:Callback<Handled<Error>>) -> {
      session.write(c, o -> OnMainThread.run(() -> cb.invoke(switch o {
        case Success(_): Resume;
        case Failure(e): Clog(e);
      })));
    }));

    if (!options.end)
      return body.map(c -> c.toResult(Noise));

    return body.flatMap(function(c):Future<PipeResult<EIn, Error, Noise>> {
      final result:PipeResult<EIn, Error, Noise> = c.toResult(Noise);
      return switch result {
        case AllWritten | SinkEnded(_, _):
          Future.irreversible(function(cb:PipeResult<EIn, Error, Noise>->Void)
            session.shutdown(o -> OnMainThread.run(() -> cb(switch o {
              case Success(_): result;
              case Failure(e): SinkFailed(e, endRest(result));
            })))
          );
        case SinkFailed(_, _) | SourceFailed(_):
          Future.sync(result);
      }
    });
  }

  static function endRest<EIn>(result:PipeResult<EIn, Error, Noise>):Source<EIn>
    return switch result {
      case SinkEnded(_, rest): rest;
      case _: cast Source.EMPTY;
    }

  static public inline function wrap(name:String, session:JavaTlsSession, channel:java.nio.channels.AsynchronousSocketChannel)
    return new JavaTlsSink(session);
}
#end
