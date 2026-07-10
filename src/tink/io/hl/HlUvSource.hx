#if hl
package tink.io.hl;

import tink.Chunk;
import tink.io.Source;
import tink.streams.Stream;

using tink.CoreApi;

@:allow(tink.io.hl)
class HlUvSource extends Generator<Chunk, Error> {
  function new(name:String, target:HlUvStream) {
    super(Future.irreversible(cb -> {
      target.read().handle(o -> {
        cb(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new HlUvSource(name, target));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, target:HlUvStream):RealSource
    return new HlUvSource(name, target);
}
#end
