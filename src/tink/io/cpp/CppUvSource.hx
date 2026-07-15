#if cpp
package tink.io.cpp;

import tink.Chunk;
import tink.io.Source;
import tink.streams.Stream;

using tink.CoreApi;

@:allow(tink.io.cpp)
class CppUvSource extends Generator<Chunk, Error> {
  function new(name:String, target:CppUvStream) {
    super(Future.irreversible(cb -> {
      target.read().handle(o -> {
        cb(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new CppUvSource(name, target));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, target:CppUvStream):RealSource
    return new CppUvSource(name, target);
}
#end
