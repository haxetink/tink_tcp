package tink.tcp.connections;

import tink.io.Source;
import tink.io.Sink;
import tink.tcp.Endpoint;

interface Connection {
  final source:RealSource;
  final sink:RealSink;
  final local:Endpoint;
  final peer:Endpoint;
  function abort():Void;
}
