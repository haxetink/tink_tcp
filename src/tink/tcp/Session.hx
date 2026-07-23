package tink.tcp;

import tink.io.Sink;
import tink.io.Source;
import tink.io.PipeResult;

using tink.io.Source;
using tink.CoreApi;

/** Internal: run Handler and pipe outbound IdealSource to sink with `{end: true}`. */
class Session {
  private function new() {}

  static public function run(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint, app:Handler, ?abort:Void->Void):Void {
    if (abort == null)
      abort = function() {};
    final incoming = new SessionIncoming(source, local, peer, abort);
    // `closed` exists before `app` so the Handler can subscribe immediately.
    app(incoming).pipeTo(sink, {end: true}).eager().handle(incoming.settleFromPipe);
  }
}

private class SessionIncoming implements tink.tcp.Handler.IncomingConnection {
  public var source(get, never):tink.io.Source.RealSource;
  public var local(get, never):tink.tcp.Endpoint;
  public var peer(get, never):tink.tcp.Endpoint;
  public var closed(get, never):tink.core.Future<tink.tcp.SessionOutcome>;

  final _source:tink.io.Source.RealSource;
  final _local:tink.tcp.Endpoint;
  final _peer:tink.tcp.Endpoint;
  final _abort:Void->Void;
  final _closed:tink.core.Future.FutureTrigger<tink.tcp.SessionOutcome>;
  var aborted = false;

  public function new(source:tink.io.Source.RealSource, local:tink.tcp.Endpoint, peer:tink.tcp.Endpoint, abort:Void->Void) {
    this._source = source;
    this._local = local;
    this._peer = peer;
    this._abort = abort;
    this._closed = tink.core.Future.trigger();
  }

  function get_source()
    return _source;

  function get_local()
    return _local;

  function get_peer()
    return _peer;

  function get_closed()
    return _closed;

  public function abort():Void {
    if (aborted)
      return;
    // Settle Aborted synchronously before the platform hard-close thunk.
    aborted = true;
    _closed.trigger(Aborted);
    _abort();
  }

  public function settleFromPipe(result:PipeResult<tink.core.Noise, tink.core.Error, tink.core.Noise>):Void {
    // Abort wins: never overwrite Aborted (or any prior settlement).
    if (aborted)
      return;
    _closed.trigger(switch result {
      case AllWritten | SinkEnded(_, _): GoneGraceful;
      case SinkFailed(e, _): Failed(e);
    });
  }
}
