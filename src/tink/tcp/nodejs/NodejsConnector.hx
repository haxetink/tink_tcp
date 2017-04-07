package tink.tcp.nodejs;

using tink.io.Sink;
using tink.io.Source;
using tink.CoreApi;

class NodejsConnector {
  static public function connect(to:Endpoint, handler:Handler):Promise<Noise> 
    return Future.async(function (cb) {
      var native = to.secure ? js.node.Tls.connect(to.port, to.host) : js.node.Net.connect(to.port, to.host);
      
      native.on('error', function (e:{ code:String, message:String }) 
        handler.handle({ 
          stream: new Error('${e.code} - Failed connecting to $to because ${e.message}'), 
          from: to, 
          to: { host: '', port: -1 },
          closed: new Future(function (_) return null),
        }).handle(function () cb(Success(Noise)))
      );
      
      native.on('connect', function () {
        
        native.removeAllListeners();//should be safe to do

        var sourceClosed = Future.trigger();

        var stream = Source.ofNodeStream('Incoming stream of connection to $to', native, { onEnd: sourceClosed.trigger.bind(Noise) }),
            local:Endpoint = { host: native.localAddress, port: native.localPort };

        var out = 'Outgoing stream of connection to $to';

        handler.handle({ from: to, to: local, stream: stream, closed: sourceClosed }).handle(function (outgoing) {
          outgoing.stream.pipeTo(
            Sink.ofNodeStream(out, native), { end: true }
          ).handle(function (o) {
            (
              if (outgoing.allowHalfOpen) sourceClosed
              else Future.sync(Noise)
            ).handle(function () {
              native.destroy();
              cb(switch o {
                case SinkFailed(e, _): Failure(e);
                case SinkEnded(_, { depleted: false }): Failure(new Error('$out closed before all data could be written'));
                default: Success(Noise);
              });
            });
              
          });
        });
      });
    });
}