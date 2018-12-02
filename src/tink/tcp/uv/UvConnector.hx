package tink.tcp.uv;

import hxuv.*;
import tink.uv.Error as UvError;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;

class UvConnector {
  static public function connect(to:Endpoint, handler:Handler):Promise<Noise> {
    return tink.uv.Host.resolve(to.host, V4)
      .next(function(ip) {
        return Future.async(function(cb) {
          var client = Tcp.alloc();
          client.connect(ip, to.port, function(status) {
            if(status == 0) {
              var wrapper = new tink.io.uv.UvStreamWrapper(client);
              var stream = new tink.io.uv.UvStreamSource('TODO', wrapper);
              var sink = new tink.io.uv.UvStreamSink('TODO', wrapper);
              var local = client.getsockname();
              handler.handle({ from: to, to: {host: local.host, port: local.port}, stream: stream, closed: wrapper.closed }).handle(function (outgoing) {
                outgoing.stream.pipeTo(sink, { end: true }).handle(function (o) {
                  (
                    if (outgoing.allowHalfOpen) wrapper.closed
                    else Future.sync(Noise)
                  ).handle(function () { 
                    cb(switch o {
                      case SinkFailed(e, _): Failure(e);
                      case SinkEnded(_, { depleted: false }): Failure(new Error('Outgoing stream closed before all data could be written'));
                      default: Success(Noise);
                    });
                  });
                });
              });
            } else {
              cb(Failure(UvError.ofStatus(status)));
            }
          });
        });
      });
  }
}