package;

import tink.tcp.*;
import tink.tcp.nodejs.NodejsConnector;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;


class RunTests {
  static function main() {

    NodejsConnector.connect({ host: 'example.com', port: 80 }, function (i:Incoming):Outgoing {
      trace(i.from);
      trace(i.to);
      //i.stream.all().handle(function (o) trace(Std.string(o)));
      i.stream.pipeTo(Sink.ofNodeStream('stdout', js.Node.process.stdout)).handle(function (o) trace(Std.string(o)));
       
      return {
        stream: 'GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n',
        allowHalfOpen: true,
      };
    }).handle(function (o) trace(Std.string(o)));
    
  }
}