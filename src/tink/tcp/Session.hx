package tink.tcp;

import tink.io.Sink;
import tink.io.Source;

using tink.io.Source;

/** Internal: run Handler and pipe outbound IdealSource to sink with `{end: true}`. */
class Session {
  private function new() {}

  static public function run(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint, app:Handler, ?abort:Void->Void):Void {
    if (abort == null)
      abort = function() {};
    app(new SessionIncoming(source, local, peer, abort)).pipeTo(sink, {end: true}).eager();
  }
}

private class SessionIncoming implements tink.tcp.Handler.IncomingConnection {
  public var source(get, never):tink.io.Source.RealSource;
  public var local(get, never):tink.tcp.Endpoint;
  public var peer(get, never):tink.tcp.Endpoint;

  final _source:tink.io.Source.RealSource;
  final _local:tink.tcp.Endpoint;
  final _peer:tink.tcp.Endpoint;
  final _abort:Void->Void;
  var aborted = false;

  public function new(source:tink.io.Source.RealSource, local:tink.tcp.Endpoint, peer:tink.tcp.Endpoint, abort:Void->Void) {
    this._source = source;
    this._local = local;
    this._peer = peer;
    this._abort = abort;
  }

  function get_source()
    return _source;

  function get_local()
    return _local;

  function get_peer()
    return _peer;

  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    _abort();
  }
}
