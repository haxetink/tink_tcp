#if java
package tink.io.java;

import tink.streams.Stream;
import tink.Chunk;

using tink.CoreApi;

@:allow(tink.io.java)
class JavaTlsSource extends Generator<Chunk, Error> {
  final name:String;
  final session:JavaTlsSession;

  function new(name:String, session:JavaTlsSession) {
    this.name = name;
    this.session = session;
    super(Future.irreversible((cb:Callback<Step<Chunk, Error>>) -> {
      session.read(o -> {
        OnMainThread.run(() -> {
          cb.invoke(switch o {
            case Success(null): End;
            case Success(chunk): Link(chunk, new JavaTlsSource(name, session));
            case Failure(e): Fail(e);
          });
        });
      });
    }));
  }

  static public inline function wrap(name:String, session:JavaTlsSession)
    return new JavaTlsSource(name, session);
}
#end