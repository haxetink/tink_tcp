package tink.tcp;

using tink.io.Source;

typedef Outgoing = {
  var stream(default, never):IdealSource;
  @:optional var allowHalfOpen(default, never):Bool;
}