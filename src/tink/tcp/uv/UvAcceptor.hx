package tink.tcp.uv;

#if !macro
import hxuv.*;
import tink.tcp.OpenPort;
import tink.uv.Error as UvError;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;
#end

class UvAcceptor {
#if !macro
  static public var inst(default, null):UvAcceptor = new UvAcceptor();
  function new() {}
  
  public function bind(port = 0):Promise<OpenPort> {
    return Future.async(function(cb) {
      var server = Tcp.alloc();
      var trigger:SignalTrigger<Session> = Signal.trigger();
      check(server.bind('0.0.0.0', port, 0));
      check(server.listen(128, function(_) {
        var client = Tcp.alloc();
        check(server.accept(client));
        var wrapper = new tink.io.uv.UvStreamWrapper(client);
        trigger.trigger({
          sink: cast new tink.io.uv.UvStreamSink('TODO', wrapper),
          incoming: {
            from: cast client.getpeername(),
            to: cast client.getsockname(),
            stream: new tink.io.uv.UvStreamSource('TODO', wrapper),
            closed: wrapper.closed,
          },
          destroy: function() {} // TODO
        });
      }));
      cb(Success(new OpenPort(trigger, server.getsockname().port)));
    });
  }
  
#end
  
  macro function check(ethis, expr) {
    return macro switch ($expr) {
      case 0: null;
      case code: cb(Failure(UvError.ofStatus(code))); return;
    }
  }
}