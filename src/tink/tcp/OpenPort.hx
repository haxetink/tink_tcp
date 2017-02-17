package tink.tcp;

import tink.streams.Stream;
import tink.streams.IdealStream;
import tink.tcp.Handler;

using tink.io.Sink;
using tink.CoreApi;

typedef Session = {
  var incoming(default, never):Incoming;
  var sink(default, never):IdealSink;
  function destroy():Void;
}

class Limitter {
  
  var queue:List<Lazy<Future<Noise>>> = new List();

  public var queued(get, never):Int;
    inline function get_queued() 
      return queue.length;

  public var running(default, null):Int = 0;

  public var maxQueued:Int = 0;
  public var maxRunning:Int = 0x100000;

  public function new() {}

  function next() {
    if (running < maxRunning)
      switch queue.pop() {
        case null: 
        case v: 
          running++;
          v.get().handle(function () {
            running--;
            next();
          });
      }
  }

  public function run<Result>(f:Void->Future<Result>):Option<Future<Result>> 
    return 
      if (running + queued >= maxQueued + maxRunning)
        None;
      else 
        Some(Future.async(function (cb) {
          queue.add(function () {
            var ret = f();
            ret.handle(cb);
            return ret.map(function (_) return Noise);
          });
          next();
        }));
}

typedef Scheduler = {
  function run<Result>(f:Void->Future<Result>):Option<Future<Result>>;
  function clear():Void;
}

class OpenPort {

  var _shutdown:Void->Promise<Noise>;
  var trigger:FutureTrigger<Handler> = Future.trigger();
  var handler:Future<Handler>;
  var scheduler:Scheduler;
  
  static function justRun<R>(f:Void->Future<R>) return Some(f());

  public function new(accepted:Signal<Session>, ?scheduler:Scheduler) {
    this.handler = trigger;
    this.scheduler = switch scheduler {
      case null: { run: justRun, clear: function () {} };
      case v: v;
    }
    accepted.handle(handleSession);
  }
  var running:Array<Session> = [];
  function handleSession(s:Session) 
    switch this.scheduler.run(function () return 
      this.handler.flatMap(function (handler) {
        return handler.handle(s.incoming).flatMap(function (out) {
          return out.stream.pipeTo(s.sink, { end: true }).flatMap(function (p):Promise<Noise> return switch p {
            case AllWritten | SinkEnded(_, { depleted: true }):
              (
                if (out.allowHalfOpen) s.incoming.closed
                else Future.sync(Noise)
              );            
            case SinkEnded(_, _):
              new Error('Outgoing stream to ${s.incoming.from} closed unexpectedly');

          });
        });
      })
    ) {
      case None: s.destroy();
      case Some(f): 
        running.push(s);
        f.handle(function () {
          if (running != null)
            switch running.indexOf(s) {
              case -1: 
              case v:
                var last = running.pop();
                if (last != s)
                  running[v] = last;
            }
          s.destroy();
        });
    }

  public function setHandler(handler:Handler) 
    switch [trigger, handler] {
      case [null, null]:
        this.handler = this.trigger = Future.trigger();
      case [null, v]:
        this.handler = Future.sync(v);
      case [v, null]:
      case [t, h]:
        this.trigger = null;
        t.trigger(h);
    }

  public function shutdown(?hard:Bool):Promise<Bool> {
    this.scheduler = { run: function (_) return None, clear: function () {} };
    if (hard) {
      for (s in this.running)
        s.destroy();
      this.running = [];
    }
    return true;
  }
  
}