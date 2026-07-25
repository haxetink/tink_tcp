#if cpp
package tink.tcp.internal.cpp;

/** One-time native process setup for UV TCP. */
class UvProcess {
  static var sigpipeIgnored = false;

  public static function ignoreSigpipe():Void {
    if (sigpipeIgnored)
      return;
    sigpipeIgnored = true;
    // Linux: writing to a reset TCP peer can raise SIGPIPE (process exit 141).
    untyped __cpp__('signal(SIGPIPE, SIG_IGN)');
  }
}
#end
