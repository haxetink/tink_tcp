package;

#if (nodejs || java || hl || cpp || (eval && eval_tls))
import haxe.io.Bytes;
import tink.io.*;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;

@:asserts
class TlsTest {
  final cert = Bytes.ofString(TlsFixtures.certPem);
  final key = Bytes.ofString(TlsFixtures.keyPem);
  final client:Client =
    #if java
    new tink.tcp.clients.JavaClient();
    #elseif eval
    new tink.tcp.clients.EvalClient();
    #elseif hl
    new tink.tcp.clients.HlClient();
    #elseif cpp
    new tink.tcp.clients.CppClient();
    #else
    new tink.tcp.clients.NodeClient();
    #end

  public function new() {}

  @:describe('TLS server/client round trip using options.tls')
  public function tls() {
    return Server.bind({host: '127.0.0.1', port: 0}, {tls: {cert: cert, key: key}}).next(server -> {
      final body = 'OK over TLS';
      server.connected.handle(cnx -> {
        (body : RealSource).pipeTo(cnx.sink, {end: true});
        cnx.source.all(); // drain, matching TestConnect
      });

      client.connect({
        host: #if (eval || hl || cpp) '127.0.0.1' #else 'localhost' #end,
        port: server.port
      }, {tls: {ca: cert, servername: 'localhost'}})
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
