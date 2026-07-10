package;

import tink.io.*;
import tink.tcp.*;

using StringTools;
using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestConnect {
  final client:Client =
    #if java
    (new tink.tcp.clients.JavaClient() : Client);
    #elseif eval
    (new tink.tcp.clients.EvalClient() : Client);
    #elseif hl
    (new tink.tcp.clients.HlClient() : Client);
    #else
    (new tink.tcp.clients.NodeClient() : Client);
    #end

  public function new() {}

  @:describe('Read from a web server')
  public function connect() {
    return Server.bind(0).next(server -> {
      server.connected.handle(cnx -> {
        final body = 'OK';
        final response = 'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body';
        (response : RealSource).pipeTo(cnx.sink, {end: true});
        cnx.source.all(); // drain the source, on nodejs this is required to ensure the connection is closed on the server
      });


      client.connect({host: '127.0.0.1', port: server.port})
        .next(cnx -> {
          final req:RealSource = 'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n';
          req.pipeTo(cnx.sink, {end: true}).next(_ -> cnx.source.all());
        })
        .next(chunk -> {
          asserts.assert(chunk.length > 0);
          asserts.assert(chunk.toString().startsWith('HTTP'));
        })
        .next(_ -> server.close())
        .next(_ -> asserts.done());
    });
  }
}
