package tink.tcp;

import tink.io.Sink;
import tink.io.Source;

using tink.io.Source;

/** Internal: run Handler and pipe outbound IdealSource to sink with `{end: true}`. */
class Session {
  private function new() {}

  static public function run(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint, app:Handler):Void {
    app({source: source, local: local, peer: peer}).pipeTo(sink, {end: true}).handle(_ -> {});
  }
}
