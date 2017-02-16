package tink.tcp;

using tink.io.Source;
using tink.CoreApi;

typedef Incoming = {
  var from(default, never):Endpoint;
  var to(default, never):Endpoint;
  var stream(default, never):RealSource;
  var closed(default, never):Future<Noise>;
}