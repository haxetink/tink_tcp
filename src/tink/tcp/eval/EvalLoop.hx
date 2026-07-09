#if eval
package tink.tcp.eval;

import eval.luv.Loop;

/**
  Returns the libuv loop associated with the current thread's `haxe.EventLoop`.
**/
class EvalLoop {
  public static function current():Loop {
    final events = haxe.EventLoop.getThreadLoop(sys.thread.Thread.current());
    if (events == null)
      return Loop.defaultLoop();
    return ensureNativeLoop(events);
  }

  static function ensureNativeLoop(events:haxe.EventLoop):Loop {
    if (@:privateAccess events.nativeLoop == null)
      @:privateAccess events.nativeLoop = new LuvLoopWrapper(Loop.defaultLoop());
    final wrapped:LuvLoopWrapper = cast @:privateAccess events.nativeLoop;
    return wrapped.uvLoop;
  }
}

private class LuvLoopWrapper {
  public final allowsReentrancy = false;
  public final uvLoop:Loop;

  public function new(loop:Loop) {
    this.uvLoop = loop;
  }

  public function run() {
    uvLoop.run(cast 2);
  }

  public function close() {
    switch uvLoop.close() {
      case Error(_):
        Sys.println('Some async handlers have not been closed');
      case Ok(_):
    }
  }

  public function isAlive() {
    return uvLoop.alive();
  }
}
#end
