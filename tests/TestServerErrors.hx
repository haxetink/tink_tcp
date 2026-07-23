package;

#if (nodejs || java || hl || cpp || (eval && eval_tls))
import haxe.io.Bytes;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestServerErrors {
  final cert = Bytes.ofString(TlsFixtures.certPem);
  final key = Bytes.ofString(TlsFixtures.keyPem);

  public function new() {}

  /**
    Listen-adjacent fault: TLS server + plain TCP client that writes non-TLS bytes.
    Server handshake must fail → `errors` emits; `Handler` must not run for that peer.
  **/
  @:describe('Server.errors fires on server TLS handshake failure; Handler not invoked')
  public function tlsHandshakeFailure() {
    var handlerInvoked = false;
    final sawError = Promise.trigger();
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      handlerInvoked = true;
      incoming.source.all().handle(_ -> {});
      return ('should-not-run' : IdealSource);
    }, {tls: {cert: cert, key: key}}).next(server -> {
      server.errors.handle(e -> sawError.trigger(Success(e)));
      // Plain dial (no options.tls): client writes garbage instead of a ClientHello.
      return Client.connect(server.endpoint, incoming -> {
        incoming.source.all().handle(_ -> {});
        return ('NOT_A_TLS_CLIENT_HELLO' : IdealSource);
      })
        .next(_ -> sawError)
        .next(_ -> {
          asserts.assert(!handlerInvoked, 'Handler must not run for failed TLS peer');
          return Noise;
        })
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }
}
#end
