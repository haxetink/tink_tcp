#if cpp
package tink.io.cpp;

import tink.streams.Stream;
import tink.Chunk;

using tink.CoreApi;

@:allow(tink.io.cpp)
class CppTlsSource extends Generator<Chunk, Error> {
  final name:String;
  final session:CppTlsSession;

  function new(name:String, session:CppTlsSession) {
    this.name = name;
    this.session = session;
    super(Future.irreversible((cb:Callback<Step<Chunk, Error>>) -> {
      session.read(o -> {
        cb.invoke(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new CppTlsSource(name, session));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, session:CppTlsSession)
    return new CppTlsSource(name, session);
}
#end
