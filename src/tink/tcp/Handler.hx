package tink.tcp;

import tink.io.Source;
import tink.CoreApi;
import tink.tcp.connections.Connection;

using tink.io.Source;
using tink.CoreApi;

typedef IncomingConnection = {
  final source:RealSource;
  final local:Endpoint;
  final peer:Endpoint;
  final closed:Future<SessionOutcome>;
  function abort():Void;
}

enum SessionOutcome {
  GoneGraceful;
  Aborted;
  Failed(e:Error);
}

private typedef HandlerFn = IncomingConnection->IdealSource;

@:callable
abstract Handler(HandlerFn) from HandlerFn to HandlerFn {
  public inline function new(fn:HandlerFn)
    this = fn;

  public inline function run(conn:Connection):Void {
    final closed:FutureTrigger<SessionOutcome> = Future.trigger();
    var aborted = false;
    this({
      source: conn.source,
      local: conn.local,
      peer: conn.peer,
      closed: closed,
      abort: () -> {
        if (aborted)
          return;
        aborted = true;
        closed.trigger(Aborted);
        conn.abort();
      },
    }).pipeTo(conn.sink, {end: true}).eager().handle(result -> {
      if (aborted)
        return;
      closed.trigger(switch result {
        case AllWritten | SinkEnded(_, _): GoneGraceful;
        case SinkFailed(e, _): Failed(e);
      });
    });
  }
}
