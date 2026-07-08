#if eval
package tink.io.luv;

import tink.Chunk;
import tink.io.Source;
import tink.streams.Stream;

using tink.CoreApi;

@:allow(tink.io.luv)
class LuvSource extends Generator<Chunk, Error> {
  function new(name:String, target:WrappedStream) {
    super(Future.irreversible(cb -> {
      target.read().handle(o -> {
        cb(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new LuvSource(name, target));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, target:WrappedStream):RealSource
    return new LuvSource(name, target);
}
#end