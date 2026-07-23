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
    return ensureDriver(events);
  }

  static function ensureDriver(events:haxe.EventLoop):Loop {
    final current = events.getDriver();
    if (Std.isOfType(current, LuvLoopWrapper))
      return (cast current : LuvLoopWrapper).uvLoop;
    final pending = events.getPendingDriver();
    if (pending != null && Std.isOfType(pending, LuvLoopWrapper))
      return (cast pending : LuvLoopWrapper).uvLoop;

    final isDefault = events == haxe.EventLoop.main;
    final uvLoop = if (isDefault) {
      Loop.defaultLoop();
    } else switch Loop.init() {
      case Ok(l):
        l;
      case Error(e):
        throw 'Failed to create uv_loop_t: $e';
    };
    final wrapper = new LuvLoopWrapper(uvLoop, isDefault);
    events.swapDriver(wrapper);
    return uvLoop;
  }
}

/**
  LibUV-backed `haxe.EventLoopDriver` for eval.

  Owns an async doorbell and a one-shot deadline timer on `uvLoop`. While
  `wait(maxBlock)` blocks (`maxBlock >= 0`), the async handle is referenced so
  `UV_RUN_ONCE` does not busy-spin when only driver handles exist. Outside
  waits both handles stay unreferenced so they alone do not keep the loop
  alive (`hasExternalWork`).

  `isDefault` must be `true` for the process-global default loop: `close`
  then only closes driver-owned handles and never calls `uv_loop_close`.
**/
private class LuvLoopWrapper implements haxe.EventLoopDriver {
  public final allowsReentrancy = false;
  public final uvLoop:Loop;
  final isDefault:Bool;
  var asyncHandle:Null<Async>;
  var timerHandle:Null<Timer>;
  var closed = false;

  public function new(uvLoop:Loop, isDefault:Bool) {
    this.uvLoop = uvLoop;
    this.isDefault = isDefault;
    switch Async.init(uvLoop, _ -> {}) {
      case Error(_):
        throw 'Failed to create uv_async_t wake handle';
      case Ok(async):
        asyncHandle = async;
        Handle.unref(async);
    }
    switch Timer.init(uvLoop) {
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

  public function wait(maxBlock:Float):Void {
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
    // Ref async for the blocking poll so wait(0)/wait(t) cannot busy-spin
    // when only unref'd driver handles exist.
    final async = asyncHandle;
    if (async != null)
      Handle.ref(async);
    uvLoop.run(ONCE);
    if (async != null)
      Handle.unref(async);
    stopDeadlineTimer();
  }

  public function wake():Void {
    if (closed)
      return;
    if (asyncHandle != null)
      asyncHandle.send();
  }

  public function close():Void {
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
    if (!isDefault) {
      switch uvLoop.close() {
        case Error(_):
          Sys.println('Some async handlers have not been closed');
        case Ok(_):
      }
    }
  }

  public function hasExternalWork():Bool {
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
