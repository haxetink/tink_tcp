package;

import haxe.io.Bytes;
import tink.tcp.*;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Server.BindOptions;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestAbort {
  /** Payload that would arrive only if the IdealSource completed a graceful pipe. */
  final promised = Bytes.ofString([for (i in 0...2000) 'GRACEFUL_PAYLOAD_$i'].join('|'));

  public function new() {}

  @:describe('Server.bind: mid-session abort; client does not get full graceful payload')
  public function serverAbort() {
    return runAbortSession().next(_ -> {
      asserts.assert(true);
      return asserts.done();
    });
  }

  #if java
  @:describe('JVM TLS: mid-session abort without orderly close_notify success')
  public function tlsAbort() {
    final cert = Bytes.ofString(TlsFixtures.certPem);
    final key = Bytes.ofString(TlsFixtures.keyPem);
    return runAbortSession(
      {tls: {cert: cert, key: key}},
      {tls: {ca: cert, servername: 'localhost'}},
      'localhost'
    ).next(_ -> {
      asserts.assert(true);
      return asserts.done();
    });
  }
  #end

  function runAbortSession(?bindOpts:BindOptions, ?connectOpts:ConnectOptions, ?connectHost:String):Promise<Noise> {
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      // Client sends a short body; after it arrives we abort mid-session instead of
      // completing a full outbound IdealSource success path.
      incoming.source.all().handle(_ -> {
        incoming.abort();
        incoming.abort(); // idempotent
      });
      // If abort were a no-op, this delayed IdealSource would eventually deliver
      // `promised` via graceful pipe — the client assert below would fail.
      return (Future.delay(2000, promised) : IdealSource);
    }, bindOpts).next(server -> {
      final to:Endpoint = connectHost == null ? server.endpoint : {
        host: connectHost,
        port: server.endpoint.port,
      };
      final done = Promise.trigger();
      return Client.connect(to, incoming -> {
        incoming.source.all().handle(o -> switch o {
          case Success(chunk) if (chunk.toString() == promised.toString()):
            done.trigger(Failure(new Error('full graceful payload arrived; abort likely no-op')));
          case Success(_), Failure(_):
            // Incomplete Success or Failure — not a clean FIN of the promised body.
            done.trigger(Success(Noise));
        });
        return ('client-body-not-gracefully-finished-by-peer' : IdealSource);
      }, connectOpts)
        .next(_ -> done)
        .next(_ -> server.shutdown());
    });
  }
}
