#if eval
package tink.tcp.eval;

import eval.luv.Async;
import eval.luv.Handle;
import eval.luv.Loop;
import eval.luv.Timer;

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

/**
  NativeEventLoop adapter: blocking `UV_RUN_ONCE` with an async wake doorbell
  and a one-shot UV timer for the next Haxe EventLoop deadline.
  Mirrors `hl.uv.Loop`'s LoopWrapper.
**/
private class LuvLoopWrapper {
  public final allowsReentrancy = false;
  public final uvLoop:Loop;
  var asyncHandle:Null<Async>;
  var timerHandle:Null<Timer>;
  var closed = false;

  public function new(loop:Loop) {
    this.uvLoop = loop;
    switch Async.init(loop, _ -> {}) {
      case Error(_):
        throw 'Failed to create uv_async_t wake handle';
      case Ok(async):
        asyncHandle = async;
        Handle.unref(async);
    }
    switch Timer.init(loop) {
      case Error(_):
        if (asyncHandle != null) {
          Handle.close(asyncHandle, noop);
          asyncHandle = null;
        }
        throw 'Failed to create uv_timer_t deadline handle';
      case Ok(timer):
        timerHandle = timer;
        Handle.unref(timer);
    }
  }

  public function run(maxBlock:Float) {
    if (closed)
      return;
    if (maxBlock < 0) {
      // Haxe events already due: do not sleep in the poller
      stopDeadlineTimer();
      uvLoop.run(NOWAIT);
      return;
    }
    if (maxBlock > 0)
      armDeadlineTimer(maxBlock);
    else
      stopDeadlineTimer();
    uvLoop.run(ONCE);
    stopDeadlineTimer();
  }

  public function wake() {
    if (asyncHandle != null)
      asyncHandle.send();
  }

  public function close() {
    if (closed)
      return;
    closed = true;
    stopDeadlineTimer();
    if (asyncHandle != null) {
      Handle.close(asyncHandle, noop);
      asyncHandle = null;
    }
    if (timerHandle != null) {
      Handle.close(timerHandle, noop);
      timerHandle = null;
    }
    // Drain close callbacks so loop_close can succeed
    uvLoop.run(NOWAIT);
    switch uvLoop.close() {
      case Error(_):
        Sys.println('Some async handlers have not been closed');
      case Ok(_):
    }
  }

  public function isAlive() {
    return !closed && uvLoop.alive();
  }

  function armDeadlineTimer(maxBlock:Float) {
    if (timerHandle == null)
      return;
    var ms = Math.ceil(maxBlock * 1000);
    if (ms < 1)
      ms = 1;
    if (ms > 2147483647)
      ms = 2147483647;
    timerHandle.start(noop, ms, 0);
  }

  function stopDeadlineTimer() {
    if (timerHandle != null)
      timerHandle.stop();
  }

  static function noop() {}
}
#end
