package;

import haxe.io.*;
import tink.tcp.*;

using tink.io.Source;
using tink.CoreApi;
using Lambda;

@:asserts
class EchoTest {
  final total = 10;
  final message = Bytes.ofString([for(i in 0...10000) 'Is it me you\'re looking for $i?'].join(' '));
  final echoer = 'hello\r\n';

  public function new() {}

  @:variant(this.sequential, this.message.length + this.echoer.length * this.total)
  @:variant(this.parallel, (this.message.length + this.echoer.length) * this.total)
  public function echo(fn:(Int, Endpoint) -> Promise<Int>, expected:Int) {
    return Server.bind(0, incoming ->
      (echoer : IdealSource).append(incoming.source.idealize(_ -> Source.EMPTY))
    ).next(server -> {
      fn(total, server.endpoint)
        .next(length -> asserts.assert(length == expected))
        .next(_ -> server.shutdown())
        .next(_ -> asserts.done());
    });
  }

  function sequential(total:Int, to:Endpoint) {
    var last:RealSource = message;
    return Promise.inSequence([for(i in 0...total)
      Promise.lazy(() -> {
        final outbound = last;
        return Client.connect(to, incoming -> {
          last = incoming.source;
          return outbound.idealize(_ -> Source.EMPTY);
        });
      })
    ])
      .next(_ -> last.all())
      .next(chunk -> chunk.length);
  }

  function parallel(total:Int, to:Endpoint) {
    return Promise.inParallel([for(i in 0...total) {
      final got = Promise.trigger();
      Client.connect(to, incoming -> {
        incoming.source.all().handle(got.trigger);
        return (message : IdealSource);
      }).next(_ -> got).next(chunk -> chunk.length);
    }]).next(v -> v.fold((v, total) -> total + v, 0));
  }
}
