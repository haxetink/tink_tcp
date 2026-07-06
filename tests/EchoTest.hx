package;

import haxe.io.*;
import tink.io.Sink;
import tink.tcp.*;

using tink.io.Source;
using tink.io.PipeResult;
using tink.CoreApi;
using Lambda;

@:asserts
class EchoTest {
  var total = 10;
  var message = Bytes.ofString([for(i in 0...10000) 'Is it me you\'re looking for $i?'].join(' '));
  var echoer = 'hello\r\n';
  var client:Client =
    #if java
    new tink.tcp.clients.JavaClient();
    #else
    new tink.tcp.clients.NodeClient();
    #end

  public function new() {}

  @:variant(this.sequential, this.message.length + this.echoer.length * this.total)
  @:variant(this.parallel, (this.message.length + this.echoer.length) * this.total)
  public function echo(fn:(Int, Int) -> Promise<Int>, expected:Int) {
    var isParallel = expected == (message.length + echoer.length) * total;
    return Server.bind(0).next(server -> {
      var echoed = 0;
      var serverTask = Future.trigger();
      server.connected.handle(function(cnx) {
        (echoer : RealSource).append(cnx.source).pipeTo(cnx.sink, {end: true})
          .handle(v -> {
            var ok = switch v {
              case AllWritten: true;
              case SinkEnded(_, _): isParallel;
              default: false;
            };
            asserts.assert(ok);
            if (++echoed == total) serverTask.trigger(Noise);
          });
      });

      var clientTask = fn(total, server.port)
        .next(length -> asserts.assert(length == expected));

      Promise.inParallel([serverTask, clientTask])
        .next(_ -> server.close())
        .next(_ -> asserts.done());
    });
  }

  function sequential(total:Int, port:Int) {
    var last:RealSource = message;
    var promise = Promise.inSequence([for(i in 0...total)
      Promise.lazy(() -> {
        client.connect(port).next(cnx -> {
          last.pipeTo(cnx.sink, {end: true}).next(result -> {
            last = cnx.source;
          });
        });
      })
    ]);
    return promise
      .next(_ -> last.all())
      .next(chunk -> chunk.length);
  }

  function parallel(total:Int, port:Int) {
    return Promise.inParallel([for(i in 0...total) {
      client.connect(port).next(cnx -> {
        var write:RealSource = message;
        return write.pipeTo(cnx.sink, {end: true})
          .next(_ -> cnx.source.all())
          .next(chunk -> chunk.length);
      });
    }]).next(v -> v.fold((v, total) -> total + v, 0));
  }
}