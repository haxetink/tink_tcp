package tink.tcp;

import tink.io.Source;

interface IncomingConnection {
  var source(get, never):RealSource;
  var local(get, never):Endpoint;
  var peer(get, never):Endpoint;
  function abort():Void;
}

typedef Handler = IncomingConnection->IdealSource;
