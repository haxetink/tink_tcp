#if eval
package tink.io.eval;

import tink.streams.Stream;
import tink.Chunk;

using tink.CoreApi;

@:allow(tink.io.eval)
class EvalTlsSource extends Generator<Chunk, tink.core.Error> {
  final name:String;
  final session:EvalTlsSession;

  function new(name:String, session:EvalTlsSession) {
    this.name = name;
    this.session = session;
    super(Future.async(function(cb:Callback<Step<Chunk, tink.core.Error>>) {
      session.read(function(o) {
        cb.invoke(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new EvalTlsSource(name, session));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, session:EvalTlsSession)
    return new EvalTlsSource(name, session);
}
#end
