#if hl
package tink.io.hl;

import tink.streams.Stream;
import tink.Chunk;

using tink.CoreApi;

@:allow(tink.io.hl)
class HlTlsSource extends Generator<Chunk, tink.core.Error> {
  final name:String;
  final session:HlTlsSession;

  function new(name:String, session:HlTlsSession) {
    this.name = name;
    this.session = session;
    super(Future.irreversible((cb:Callback<Step<Chunk, tink.core.Error>>) -> {
      session.read(o -> {
        cb.invoke(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new HlTlsSource(name, session));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, session:HlTlsSession)
    return new HlTlsSource(name, session);
}
#end
