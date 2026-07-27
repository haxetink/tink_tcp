package;

import haxe.io.Bytes;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestSessionClosed {
  public function new() {}

  @:describe('closed → GoneGraceful when finite IdealSource completes and peer drains')
  public function graceful() {
    final payload = 'graceful-body';
    final serverClosed = Promise.trigger();
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      // Subscribe immediately; closed exists before the Handler body continues.
      incoming.closed.handle(o -> serverClosed.trigger(Success(o)));
      incoming.source.all().handle(_ -> {});
      return (payload : IdealSource);
    }).next(server -> {
      final clientGot = Promise.trigger();
      return Client.connect(server.endpoint, incoming -> {
        incoming.source.all().handle(clientGot.trigger);
        return ('client-done' : IdealSource);
      })
        .next(_ -> clientGot)
        .next(chunk -> asserts.assert(chunk.toString() == payload))
        .next(_ -> serverClosed)
        .next(o -> switch o {
          case GoneGraceful:
            asserts.assert(true);
          case other:
            asserts.assert(false, 'expected GoneGraceful, got $other');
        })
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }

  @:describe('closed → Aborted when abort() before outbound finishes (not Failed)')
  public function abortClosed() {
    final promised = Bytes.ofString([for (i in 0...2000) 'STILL_SENDING_$i'].join('|'));
    final serverClosed = Promise.trigger();
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      incoming.closed.handle(o -> serverClosed.trigger(Success(o)));
      // Abort mid-session once the client body arrives — outbound IdealSource has not finished.
      incoming.source.all().handle(_ -> incoming.abort());
      return (Future.delay(2000, promised) : IdealSource);
    }).next(server -> {
      return Client.connect(server.endpoint, incoming -> {
        incoming.source.all().handle(_ -> {});
        return ('ping' : IdealSource);
      })
        .next(_ -> serverClosed)
        .next(o -> switch o {
          case Aborted:
            asserts.assert(true);
          case Failed(e):
            asserts.assert(false, 'expected Aborted, not Failed(${e.message})');
          case GoneGraceful:
            asserts.assert(false, 'expected Aborted, not GoneGraceful');
        })
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }

  @:describe('closed → Failed when peer hard-closes while IdealSource still producing')
  public function outboundFailure() {
    final serverClosed = Promise.trigger();
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      incoming.closed.handle(o -> serverClosed.trigger(Success(o)));
      incoming.source.all().handle(_ -> {});
      // Keep producing until the peer hard-close clogs the sink. A single finite body can
      // still land in the kernel send buffer after abort and race to AllWritten/GoneGraceful
      // (especially on JVM JavaSocketSink).
      return pumpingOutbound();
    }).next(server -> {
      return Client.connect(server.endpoint, incoming -> {
        // Let a little data flow, then hard-close while the server is still pumping.
        incoming.source.limit(1024).all().handle(_ -> incoming.abort());
        return ('client-ping' : IdealSource);
      })
        .next(_ -> serverClosed)
        .next(o -> switch o {
          case Failed(_):
            asserts.assert(true);
          case GoneGraceful:
            asserts.assert(false, 'expected Failed, not GoneGraceful (accidental drain?)');
          case Aborted:
            asserts.assert(false, 'expected Failed, not Aborted (server did not abort)');
        })
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }

  /** Non-trivial IdealSource that keeps emitting until pipeTo clogs or the test ends. */
  static function pumpingOutbound():IdealSource {
    final chunk = Bytes.ofString([for (_ in 0...8192) 'W'].join(''));
    return (chunk : IdealSource).append((Future.delay(1, Noise).map(_ -> pumpingOutbound()) : IdealSource));
  }
}
