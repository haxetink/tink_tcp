package;

#if (nodejs || java || hl || cpp || (eval && eval_tls))
import haxe.io.Bytes;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class TlsTest {
  final cert = Bytes.ofString(TlsFixtures.certPem);
  final key = Bytes.ofString(TlsFixtures.keyPem);

  public function new() {}

  @:describe('TLS server/client round trip using options.tls')
  public function tls() {
    final body = 'OK over TLS';
    // Bind with TLS; Handler returns IdealSource.
    return Server.bind({host: '127.0.0.1', port: 0}, incoming -> {
      incoming.source.all().handle(_ -> {});
      return (body : IdealSource);
    }, {tls: {cert: cert, key: key}}).next(server -> {
      // Dial host: localhost for SNI on node/jvm; 127.0.0.1 elsewhere (cert SAN covers both).
      final to:Endpoint = {
        host: #if (eval || hl || cpp) '127.0.0.1' #else 'localhost' #end,
        port: server.endpoint.port,
      };
      final got = Promise.trigger();
      Client.connect(to, incoming -> {
        incoming.source.all().handle(got.trigger);
        return Source.EMPTY;
      }, {tls: {ca: cert, servername: 'localhost'}})
        .next(_ -> got) // dial succeeded; assert session I/O via stream, not connect lifetime
        .next(chunk -> asserts.assert(chunk.toString() == body))
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }
}
#end
