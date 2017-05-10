package tink.tcp.nodejs;

import tink.tcp.OpenPort;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;

@:require(nodejs)
class NodejsAcceptor {
  static public var inst(default, null):NodejsAcceptor = new NodejsAcceptor();
  function new() {}
  public function bind(?port:Int):Promise<OpenPort> 
    return Future.async(function (cb) {
      
      var s = new SignalTrigger<Session>();
      var server = js.node.Net.createServer({ allowHalfOpen: true }, function (cnx) {

        var from:Endpoint = {
          host: cnx.remoteAddress,
          port: cnx.remotePort,
        };

        var to:Endpoint = {
          host: cnx.localAddress,
          port: cnx.localPort,
        };

        var closed = Future.trigger();
        var stream = Source.ofNodeStream('Inbound stream from $to', cnx, { onEnd: closed.trigger.bind(Noise) });

        s.trigger({
          sink: cast Sink.ofNodeStream('Outbound stream to $from', cnx),
          incoming: { from: from, to: to, stream: stream, closed: closed },
          destroy: function () cnx.destroy()
        });
      });
      
      server.on('error', function (e:{ code:String, message:String }) cb(
        Failure(new Error('${e.code} - Failed bindg port $port because ${e.message}'))
      )).on('listening', function () cb(
        Success(new OpenPort(s, server.address().port))
      ))
      .listen(switch port {
        case null: 0;
        case v: v;
      });
    });

}