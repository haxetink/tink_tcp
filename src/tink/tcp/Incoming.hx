package tink.tcp;

using tink.io.Source;

typedef Incoming = {
  var from(default, never):Endpoint;
  var to(default, never):Endpoint;
  var stream(default, never):RealSource;
}