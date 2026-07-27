#if cpp
package tink.tcp.internal.cpp;

import cpp.*;
import haxe.io.Bytes;
import tink.Chunk;
import tink.tcp.Endpoint;
import uv.*;
import uv.Native.UvHandle;
import uv.Native.UvStream;
import uv.Native.UvWrite;
import uv.Native.UvShutdown;
import uv.Buf.Buf_t;

using tink.CoreApi;

typedef CppReadOutcome = Outcome<Null<Chunk>, Error>;

private class WriteCtx {
  public final stream:CppTcpSession;
  public final buf:Buf;
  public final cb:Callback<Outcome<Bool, Error>>;
  public function new(stream:CppTcpSession, buf:Buf, cb:Callback<Outcome<Bool, Error>>) {
    this.stream = stream;
    this.buf = buf;
    this.cb = cb;
  }
}

private class EndCtx {
  public final stream:CppTcpSession;
  public final cb:Callback<Outcome<Bool, Error>>;
  public function new(stream:CppTcpSession, cb:Callback<Outcome<Bool, Error>>) {
    this.stream = stream;
    this.cb = cb;
  }
}

/**
  Async TCP stream over linc_uv. Callbacks use `setData` + static Callables.
**/
class CppTcpSession implements tink.tcp.internal.TcpSession {
  /** GC roots: uv handle/req `data` is a raw pointer, not a Haxe root. */
  static final liveSessions:Array<CppTcpSession> = [];
  static final liveConnectCtx:Array<Dynamic> = [];

  final name:String;
  public final tcp:Tcp;
  final stream:Stream;
  final chunkSize:Int;

  var readActive = false;
  var readEnded = false;
  var readWaiters:Array<Callback<CppReadOutcome>> = [];
  var readQueue:Array<Chunk> = [];

  var writeEnded = false;
  var closed = false;
  /** Keep write/shutdown contexts alive until UV callbacks (setData is not a GC root). */
  final pendingWriteCtxs:Array<WriteCtx> = [];
  final pendingEndCtxs:Array<EndCtx> = [];

  public function new(name:String, tcp:Tcp, ?chunkSize:Int = 0x10000) {
    this.name = name;
    this.tcp = tcp;
    this.stream = tcp.asStream();
    this.chunkSize = chunkSize;
    // Keep PointerType abstracts in locals before method calls (hxcpp PointerReference).
    stream.setData(this);
    final h = stream.asHandle();
    h.ref();
    liveSessions.push(this);
  }

  public function read():Promise<Null<Chunk>> {
    return Future.irreversible(cb -> {
      if (readQueue.length > 0) {
        cb(Success(readQueue.shift()));
      } else if (readEnded) {
        cb(Success(null));
      } else {
        readWaiters.push(cb);
        startReading();
      }
    });
  }

  function startReading() {
    if (readActive || readEnded)
      return;
    readActive = true;
    stream.readStart(Callable.fromStaticFunction(onAlloc), Callable.fromStaticFunction(onRead));
  }

  @:unreflective
  static function onAlloc(handle:Star<UvHandle>, suggestedSize:SizeT, buf:Star<Buf_t>) {
    final size:Int = cast suggestedSize;
    buf.base = untyped __cpp__('(char*){0}', Stdlib.nativeMalloc(size));
    buf.len = cast size;
  }

  @:unreflective
  static function onRead(handle:Star<UvStream>, nread:SSizeT, buf:ConstStar<Buf_t>) {
    final n:Int = cast nread;
    final s:Stream = Native.stream(handle);
    final self:CppTcpSession = s.getData();
    if (self == null) {
      Buf.unmanaged(buf).free();
      return;
    }
    if (n > 0) {
      final out = Bytes.alloc(n);
      Buf.unmanaged(buf).copyToBytes(out, n);
      final chunk:Chunk = out;
      if (self.readWaiters.length > 0) {
        final waiter = self.readWaiters.shift();
        waiter.invoke(Success(chunk));
      } else
        self.readQueue.push(chunk);
    }
    if (n < 0) {
      self.finishReading();
      self.completeWaiters(Success(null));
    }
    Buf.unmanaged(buf).free();
  }

  function finishReading() {
    if (readActive) {
      stream.readStop();
      readActive = false;
    }
  }

  function completeWaiters(result:CppReadOutcome) {
    switch result {
      case Success(null):
        readEnded = true;
        tryClose();
      default:
    }
    while (readWaiters.length > 0)
      readWaiters.shift().invoke(result);
  }

  public function write(chunk:Chunk):Promise<Bool> {
    return Future.irreversible(cb -> {
      if (closed || writeEnded) {
        cb(Failure(uvError(-1, 'Write failed for "$name" (closed)')));
        return;
      }
      if (chunk.length == 0) {
        cb(Success(true));
        return;
      }
      final bytes = chunk.toBytes();
      final writeReq = new Write();
      final writeBuf = new Buf();
      writeBuf.alloc(bytes.length);
      writeBuf.copyFromBytes(bytes, bytes.length);
      final ctx = new WriteCtx(this, writeBuf, cb);
      pendingWritesRetain(ctx);
      writeReq.setData(ctx);
      final status = stream.write(writeReq, writeBuf, 1, Callable.fromStaticFunction(onWrite));
      if (status != 0) {
        pendingWritesRelease(ctx);
        writeBuf.freeBase();
        cb(Failure(uvError(status, 'Write failed for "$name"')));
      }
    });
  }

  @:unreflective
  static function onWrite(req:Star<UvWrite>, status:Int) {
    final writeReq:Write = Native.write(req);
    final ctx:WriteCtx = writeReq.getData();
    if (ctx == null)
      return;
    ctx.stream.pendingWritesRelease(ctx);
    ctx.buf.freeBase();
    if (status == 0)
      ctx.cb.invoke(Success(true));
    else
      ctx.cb.invoke(Failure(uvError(status, 'Write failed for "${ctx.stream.name}"')));
  }

  public function end():Promise<Bool> {
    return Future.irreversible(cb -> {
      if (writeEnded) {
        cb(Success(false));
        return;
      }
      writeEnded = true;
      final shutdownReq = new Shutdown();
      final ctx = new EndCtx(this, cb);
      pendingEndRetain(ctx);
      shutdownReq.setData(ctx);
      final status = stream.shutdown(shutdownReq, Callable.fromStaticFunction(onShutdown));
      if (status != 0) {
        pendingEndRelease(ctx);
        tryClose();
        cb(Failure(uvError(status, 'Shutdown failed for "$name"')));
      }
    });
  }

  @:unreflective
  static function onShutdown(req:Star<UvShutdown>, status:Int) {
    final shutdownReq:Shutdown = Native.shutdown(req);
    final ctx:EndCtx = shutdownReq.getData();
    if (ctx == null)
      return;
    ctx.stream.pendingEndRelease(ctx);
    if (status != 0) {
      ctx.cb.invoke(Failure(uvError(status, 'Shutdown failed for "${ctx.stream.name}"')));
      return;
    }
    ctx.stream.tryClose();
    ctx.cb.invoke(Success(false));
  }

  function pendingWritesRetain(ctx:WriteCtx)
    pendingWriteCtxs.push(ctx);

  function pendingWritesRelease(ctx:WriteCtx) {
    pendingWriteCtxs.remove(ctx);
    maybeReleaseLive();
  }

  function pendingEndRetain(ctx:EndCtx)
    pendingEndCtxs.push(ctx);

  function pendingEndRelease(ctx:EndCtx) {
    pendingEndCtxs.remove(ctx);
    maybeReleaseLive();
  }

  function maybeReleaseLive() {
    if (closed && pendingWriteCtxs.length == 0 && pendingEndCtxs.length == 0)
      liveSessions.remove(this);
  }

  function tryClose() {
    if (!closed && readEnded && writeEnded)
      doClose();
  }

  function doClose() {
    if (closed)
      return;
    final h = stream.asHandle();
    if (h.isClosing())
      return;
    closed = true;
    finishReading();
    h.close(Callable.fromStaticFunction(onClose));
  }

  @:unreflective
  static function onClose(handle:Star<UvHandle>) {
    final h:Handle = Native.handle(handle);
    final self:CppTcpSession = h.getData();
    if (self != null)
      self.maybeReleaseLive();
  }

  public function close() {
    doClose();
  }

  /**
    Best-effort hard close: end/fail pending read waiters, mark read/write ended so a later
    `end()` (UV shutdown) is a no-op, then close the handle without graceful shutdown.
  **/
  public function abort():Void {
    if (writeEnded && readEnded && closed)
      return;
    writeEnded = true;
    readEnded = true;
    finishReading();
    while (readWaiters.length > 0)
      readWaiters.shift().invoke(Success(null));
    doClose();
  }

  public function getLocalEndpoint():Endpoint {
    return endpointFrom(tcp.getSockAddress());
  }

  public function getPeerEndpoint():Endpoint {
    return endpointFrom(tcp.getPeerAddress());
  }

  static function endpointFrom(addr:{host:String, port:Int}):Endpoint {
    return {host: addr.host, port: addr.port};
  }

  static function uvError(code:Int, message:String):Error {
    return Error.withData('$message: ${Std.string(Uv.err_name(code))}', code);
  }
}
#end
