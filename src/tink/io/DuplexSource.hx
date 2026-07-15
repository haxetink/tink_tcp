package tink.io;

import tink.Chunk;
import tink.io.Source;
import tink.streams.Stream;

using tink.CoreApi;

class DuplexSource extends Generator<Chunk, Error> {
  function new(name:String, target:DuplexStream) {
    super(Future.irreversible(cb -> {
      target.read().handle(o -> {
        cb(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new DuplexSource(name, target));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, target:DuplexStream):RealSource
    return new DuplexSource(name, target);
}
