#if hl
package tink.tcp.hl;

import hl.uv.HandleData;

/**
  Half-close helpers. `hl.uv.Stream` has no shutdown; we provide it via `tink_tcp.hdll`
  (bytecode) or by linking `native/hl/tink_tcp_uv.c` (HL/C).
**/
class UvExtras {
  public static function shutdown(handle:HandleData, callb:Void->Void):Bool {
    return stream_shutdown(handle, callb);
  }

  @:hlNative("tink_tcp", "stream_shutdown")
  static function stream_shutdown(handle:HandleData, callb:Void->Void):Bool {
    return false;
  }
}
#end
