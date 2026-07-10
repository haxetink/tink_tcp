#if hl
package tink.io.hl;

import tink.Chunk;
import tink.io.Sink;
import tink.streams.Stream;

using tink.io.PipeResult;
using tink.CoreApi;

@:allow(tink.io.hl)
class HlUvSink extends SinkBase<Error, Noise> {
  final target:HlUvStream;

  function new(target:HlUvStream) {
    this.target = target;
  }

  override public function consume<EIn>(source:Stream<Chunk, EIn>, options:PipeOptions):Future<PipeResult<EIn, Error, Noise>> {
    final ret = source.forEach((c:Chunk) -> {
      return target.write(c).map(w -> switch w {
        case Success(true): Resume;
        case Success(false): BackOff;
        case Failure(e): Clog(e);
      });
    });

    if (options.end)
      ret.next(_ -> target.end()).eager();

    return ret.map((c) -> c.toResult(Noise));
  }

  static public inline function wrap(name:String, target:HlUvStream):RealSink
    return new HlUvSink(target);
}
#end
