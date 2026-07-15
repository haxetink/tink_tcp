package tink.io;

import tink.streams.Stream;
import tink.Chunk;

using tink.CoreApi;

class TlsSource extends Generator<Chunk, Error> {
  final name:String;
  final session:TlsSession;

  function new(name:String, session:TlsSession) {
    this.name = name;
    this.session = session;
    super(Future.irreversible((cb:Callback<Step<Chunk, Error>>) -> {
      session.read(o -> {
        cb.invoke(switch o {
          case Success(null): End;
          case Success(chunk): Link(chunk, new TlsSource(name, session));
          case Failure(e): Fail(e);
        });
      });
    }));
  }

  static public inline function wrap(name:String, session:TlsSession)
    return new TlsSource(name, session);
}
