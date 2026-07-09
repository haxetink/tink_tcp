package;

#if java
import haxe.io.Bytes;
import tink.io.*;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class JavaTlsTest {
  final cert = Bytes.ofString(TlsFixtures.certPem);
  final key = Bytes.ofString(TlsFixtures.keyPem);

  public function new() {}

  @:describe('TLS server/client round trip using options.tls')
  public function tls() {
    final client = new tink.tcp.clients.JavaClient();

    return Server.bind({host: '127.0.0.1', port: 0}, {tls: {cert: cert, key: key}}).next(server -> {
      final body = 'OK over TLS';
      server.connected.handle(cnx -> {
        (body : RealSource).pipeTo(cnx.sink, {end: true});
        cnx.source.all();
      });

      client.connect({host: 'localhost', port: server.port}, {tls: {ca: cert, servername: 'localhost'}})
        .next(cnx -> cnx.source.all())
        .next(chunk -> {
          asserts.assert(chunk.toString() == body);
        })
        .next(_ -> server.close())
        .next(_ -> asserts.done());
    });
  }
}
#end
