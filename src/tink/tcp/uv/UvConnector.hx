package tink.tcp.uv;

import cpp.*;
import uv.Uv;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;

class UvConnector {
  static public function connect(to:Endpoint, handler:Handler):Promise<Noise> {
    return tink.uv.Host.resolve(to.host, Uv.AF_INET)
      .next(function(ip) {
        return Future.async(function(cb) {
          var client = new uv.Tcp();
          client.init(uv.Loop.DEFAULT);
          var connect = new uv.Connect();
          var dest = new uv.SockAddrIn();
          dest.ip4Addr(ip, to.port);
          client.setData({
            cb: cb,
            to: to,
            handler: handler,
          });
          client.connect(connect, dest, Callable.fromStaticFunction(onConnect));
          dest.destroy();
        });
      });
  }
  
  static function onConnect(req:RawPointer<Connect_t>, status:Int) {
    var connect = uv.Connect.fromRaw(req);
    var socket = connect.handle;
    var tcp:uv.Tcp = socket;
    var data:Context = socket.getData();
    connect.destroy();
    
    if(status == 0) {
      var sourceClosed = Future.trigger();
      var wrapped = tink.io.uv.UvStreamWrapper.wrap(socket, {
        source: {name: 'TODO', onEnd: sourceClosed.trigger.bind(Noise)},
        sink: {name: 'TODO'}
      });
      var stream = wrapped.a;
      var sink = wrapped.b;
      var local = tcp.getSockAddress();
      data.handler.handle({ from: data.to, to: {host: local.host, port: local.port}, stream: stream, closed: sourceClosed }).handle(function (outgoing) {
        outgoing.stream.pipeTo(sink, { end: true }).handle(function (o) {
          (
            if (outgoing.allowHalfOpen) sourceClosed
            else Future.sync(Noise)
          ).handle(function () { 
            data.cb.invoke(switch o {
              case SinkFailed(e, _): Failure(e);
              case SinkEnded(_, { depleted: false }): Failure(new Error('Outgoing stream closed before all data could be written'));
              default: Success(Noise);
            });
          });
            
        });
      });
    } else {
      data.cb.invoke(Failure(new Error(Uv.err_name(status))));
    }
  }
}

private typedef Context = {
  handler:Handler,
  to:Endpoint,
  cb:Callback<Outcome<Noise, Error>>,
}