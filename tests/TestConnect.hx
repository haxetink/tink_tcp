package;

import tink.tcp.*;

using StringTools;
using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestConnect {
  public function new() {}

  @:describe('Read from a local echo-style HTTP responder')
  public function connect() {
    return Server.bind(0, incoming -> {
      final body = 'OK';
      final response = 'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body';
      // Drain inbound so Node closes cleanly; outbound is the returned IdealSource.
      incoming.source.all().handle(_ -> {});
      return (response : IdealSource);
    }).next(server -> {
      final got = Promise.trigger();
      Client.connect(server.endpoint, incoming -> {
        incoming.source.all().handle(got.trigger);
        return ('GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' : IdealSource);
      })
        .next(_ -> got) // dial succeeded; assert session I/O via stream, not connect lifetime
        .next(chunk -> {
          asserts.assert(chunk.length > 0);
          asserts.assert(chunk.toString().startsWith('HTTP'));
        })
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }

  @:describe('Connect Promise rejects when dial fails')
  public function connectFailure() {
    // Nothing listening on this port — dial must reject and handler must never run.
    var handlerRan = false;
    return Client.connect({host: '127.0.0.1', port: 1}, _ -> {
      handlerRan = true;
      return Source.EMPTY;
    }).asFuture().flatMap(o -> {
      asserts.assert(!o.isSuccess());
      asserts.assert(!handlerRan);
      return asserts.done();
    });
  }
}
