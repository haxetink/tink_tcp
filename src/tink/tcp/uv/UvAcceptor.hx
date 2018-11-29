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
  
  static function onConnect(handle:RawPointer<Stream_t>, status:Int):Void {
    var server:uv.Tcp = handle;
    var client = new uv.Tcp();
    client.init(uv.Loop.DEFAULT);
    
    if(server.asStream().accept(client) == 0) {
      var trigger:SignalTrigger<Session> = server.getData();
      
      var name = new uv.SockAddrStorage();
      var namelen = name.sizeof();
      var to = client.getSockName(name, cast Pointer.addressOf(namelen));
      name.destroy(); // TODO: don't alloc, use stack instead
      
      var name = new uv.SockAddrStorage();
      var namelen = name.sizeof();
      var from = client.getPeerName(name, cast Pointer.addressOf(namelen));
      name.destroy(); // TODO: don't alloc, use stack instead
      
      trigger.trigger({
        sink: cast new tink.io.uv.UvStreamSink('TODO', client),
        incoming: {
          from: from,
          to: to,
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