#if hl
package tink.tcp.internal.hl;

import hl.uv.Loop;

/**
  Returns the libuv loop associated with the current thread's `haxe.EventLoop`.
**/
class HlLoop {
  public static function current():Loop {
    return Loop.getCurrent();
  }
}
#end
