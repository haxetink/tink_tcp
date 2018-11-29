package tink.tcp.uv;

#if !macro
import cpp.*;
import uv.Uv;
import tink.tcp.OpenPort;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;
#end

class UvAcceptor {
#if !macro
  static public var inst(default, null):UvAcceptor = new UvAcceptor();
  function new() {}
  
  public function bind(port:Int):Promise<OpenPort> {
    return Future.async(function(cb) {
      var server = new uv.Tcp();
      var trigger:SignalTrigger<Session> = Signal.trigger();
      
      // TODO: handle error
      // cb(Failure(new Error(Uv.err_name(code)))); return;
      
      check(server.init(uv.Loop.DEFAULT));
      server.setData(trigger);
      var addr = new uv.SockAddrIn();
      check(addr.ip4Addr('0.0.0.0', port));
      check(server.bind(addr, 0));
      addr.destroy();
      check(server.asStream().listen(128, Callable.fromStaticFunction(onConnect)));
      
      cb(Success(new OpenPort(trigger, port)));
    });
  }
      
    //   var server = js.node.Net.createServer({ allowHalfOpen: true }, function (cnx) {

    //     var from:Endpoint = {
    //       host: cnx.remoteAddress,
    //       port: cnx.remotePort,
    //     };

    //     var to:Endpoint = {
    //       host: cnx.localAddress,
    //       port: cnx.localPort,
    //     };

    //     var closed = Future.trigger();
    //     var stream = Source.ofNodeStream('Inbound stream from $to', cnx, { onEnd: closed.trigger.bind(Noise) });

    //     s.trigger({
    //       sink: cast Sink.ofNodeStream('Outbound stream to $from', cnx),
    //       incoming: { from: from, to: to, stream: stream, closed: closed },
    //       destroy: function () cnx.destroy()
    //     });
    //   });
      
    //   server.on('error', function (e:{ code:String, message:String }) cb(
    //     Failure(new Error('${e.code} - Failed bindg port $port because ${e.message}'))
    //   )).on('listening', function () cb(
    //     Success(new OpenPort(s, server.address().port))
    //   ))
    //   .listen(switch port {
    //     case null: 0;
    //     case v: v;
    //   });
  static function onConnect(handle:RawPointer<Stream_t>, status:Int):Void {
    var server:uv.Tcp = handle;
    var client = new uv.Tcp();
    client.init(uv.Loop.DEFAULT);
    
    if(server.asStream().accept(client) == 0) {
      var trigger:SignalTrigger<Session> = server.getData();
      trigger.trigger({
        sink: Sink.BLACKHOLE, // TODO
        incoming: {
          from: {host: '', port: 0},
          to: {host: '', port: 0},
          stream: new tink.io.uv.UvStreamSource('TODO', client),
          closed: Future.trigger(),
        },
        destroy: function() {} // TODO
      });
    } else {
      client.asHandle().close(null);
    }
  }
#end

  
  macro function check(ethis, expr) {
    return macro switch ($expr) {
      case 0: null;
      case code: cb(Failure(new Error(Uv.err_name(code)))); return;
    }
  }
  
}