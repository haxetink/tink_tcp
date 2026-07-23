package tink.io;

import tink.Chunk;
import tink.io.Sink;
import tink.streams.Stream;

using tink.io.PipeResult;
using tink.io.Source;
using tink.CoreApi;

class DuplexSink extends SinkBase<Error, Noise> {
  final target:DuplexStream;

  function new(target:DuplexStream) {
    this.target = target;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, Error, Noise>> {
    final body = source.forEach((c:Chunk) -> {
      return target.write(c).map(w -> switch w {
        case Success(true): Resume;
        case Success(false): BackOff;
        case Failure(e): Clog(e);
      });
    });

    if (!options.end)
      return body.map(c -> c.toResult(Noise));

    return body.flatMap(function(c):Future<PipeResult<EIn, Error, Noise>> {
      final result:PipeResult<EIn, Error, Noise> = c.toResult(Noise);
      return switch result {
        case AllWritten | SinkEnded(_, _):
          target.end().map(function(o):PipeResult<EIn, Error, Noise> return switch o {
            case Success(_): result;
            case Failure(e): SinkFailed(e, endRest(result));
          });
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

  static public inline function wrap(name:String, target:DuplexStream):RealSink
    return new DuplexSink(target);
}
