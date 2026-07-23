package tink.tcp;

import tink.io.Source;
import tink.CoreApi;

interface IncomingConnection {
  var source(get, never):RealSource;
  var local(get, never):Endpoint;
  var peer(get, never):Endpoint;
  var closed(get, never):Future<SessionOutcome>;
  function abort():Void;
}

typedef Handler = IncomingConnection->IdealSource;
