package tink.tcp;

using tink.io.Source;

typedef Outgoing = {
  var stream(default, never):IdealSource;
  
  // if true, handler promise resolves when outgoing stream is completely sent to remote
  // otherwise it resolves when the incoming stream is also ended
  @:optional var allowHalfOpen(default, never):Bool;
}