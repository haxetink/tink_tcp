package tink.tcp;

import tink.streams.Stream;
import tink.streams.IdealStream;
import tink.tcp.Handler;

using tink.io.Sink;
using tink.CoreApi;

private typedef Session = Pair<Incoming, IdealSink>;

class OpenPort {

  var _shutdown:Void->Promise<Noise>;
  var trigger:FutureTrigger<Handler> = Future.trigger();
  var handler:Future<Handler>;
  

  public function new(incoming:IdealStream<Session>) {
    
    this.handler = trigger;
    incoming.forEach(handle);
  }

  function handle(s:Session):Future<Handled<Noise>> {
    handler.handle(function (h) h.handle(s.a).handle(function (out)
      out.stream.pipeTo(s.b, { end: true }).handle(function (o) {
        
      })
    ));
    return Future.sync(Resume);
  }

  public function setHandler(handler:Handler) {
    if (trigger != null) {
      trigger.trigger(handler);
      trigger = null;
    }
    else {
      this.handler = Future.sync(handler);
    }
  }

  public function shutdown(?hard:Bool):Promise<Bool> {
    return true;
  }
  
}