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

private typedef WriteCtx = {
  stream:CppTcpSession,
  buf:Buf,
  cb:Callback<Outcome<Bool, Error>>,
};

private typedef EndCtx = {
  stream:CppTcpSession,
  cb:Callback<Outcome<Bool, Error>>,
};

/**
  Async TCP stream over linc_uv. Callbacks use `setData` + static Callables.
**/
class CppTcpSession implements tink.tcp.internal.TcpSession {
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

  public function new(name:String, tcp:Tcp, ?chunkSize:Int = 0x10000) {
    this.name = name;
    this.tcp = tcp;
    this.stream = tcp.asStream();
    this.chunkSize = chunkSize;
    stream.asHandle().setData(this);
    stream.asHandle().ref();
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
    final self:CppTcpSession = s.asHandle().getData();
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
      if (chunk.length == 0) {
        cb(Success(true));
        return;
      }
      final bytes = chunk.toBytes();
      final writeReq = new Write();
      final writeBuf = new Buf();
      writeBuf.alloc(bytes.length);
      writeBuf.copyFromBytes(bytes, bytes.length);
      final ctx:WriteCtx = {stream: this, buf: writeBuf, cb: cb};
      writeReq.setData(ctx);
      final status = stream.write(writeReq, writeBuf, 1, Callable.fromStaticFunction(onWrite));
      if (status != 0) {
        writeBuf.freeBase();
        cb(Failure(uvError(status, 'Write failed for "$name"')));
      }
    });
  }

  @:unreflective
  static function onWrite(req:Star<UvWrite>, status:Int) {
    final writeReq:Write = Native.write(req);
    final ctx:WriteCtx = writeReq.getData();
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
      final ctx:EndCtx = {stream: this, cb: cb};
      shutdownReq.setData(ctx);
      final status = stream.shutdown(shutdownReq, Callable.fromStaticFunction(onShutdown));
      if (status != 0) {
        tryClose();
        cb(Failure(uvError(status, 'Shutdown failed for "$name"')));
      }
    });
  }

  @:unreflective
  static function onShutdown(req:Star<UvShutdown>, status:Int) {
    final shutdownReq:Shutdown = Native.shutdown(req);
    final ctx:EndCtx = shutdownReq.getData();
    if (status != 0) {
      ctx.cb.invoke(Failure(uvError(status, 'Shutdown failed for "${ctx.stream.name}"')));
      return;
    }
    ctx.stream.tryClose();
    ctx.cb.invoke(Success(false));
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
    // handle memory owned by Alloc; leave for process lifetime / GC of wrapper
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
