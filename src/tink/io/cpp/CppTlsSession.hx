#if cpp
package tink.io.cpp;

import cpp.*;
import haxe.io.Bytes;
import tink.Chunk;
import tink.tcp.cpp.mbedtls.Mbedtls;
import tink.tcp.cpp.mbedtls.NativeTls;
import tink.tcp.tls.TlsConfig;
import tink.tcp.tls.TlsContext;
import uv.*;
import uv.Native.UvHandle;
import uv.Native.UvStream;
import uv.Native.UvWrite;
import uv.Native.UvShutdown;
import uv.Buf.Buf_t;

using tink.CoreApi;

private typedef TlsWriteCtx = {
  session:CppTlsSession,
  buf:Buf,
  done:Void->Void,
};

private typedef TlsShutdownCtx = {
  session:CppTlsSession,
  cb:Callback<Outcome<Noise, Error>>,
};

@:allow(tink.io.cpp)
class CppTlsSession implements tink.io.TlsSession {
  public final tcp:Tcp;
  final stream:Stream;
  final context:TlsContext;
  /** Keeps TlsConfig (and native conf) alive for the session. */
  final config:TlsConfig;

  var netIn = Bytes.alloc(0);
  var netInPos = 0;
  var netOut = new haxe.io.BytesBuffer();

  var readActive = false;
  var writeActive = false;
  var closed = false;
  var readWaiters:Array<Void->Void> = [];
  var writeWaiter:Null<Void->Void>;

  public function new(config:TlsConfig, tcp:Tcp) {
    this.tcp = tcp;
    this.stream = tcp.asStream();
    this.config = config;
    this.context = config.createContext();
    stream.asHandle().setData(this);
    stream.asHandle().ref();
    final bioCtx:Star<cpp.Void> = untyped __cpp__('(void*){0}.GetPtr()', this);
    NativeTls.sslSetBio(context, bioCtx, Callable.fromStaticFunction(bioSend), Callable.fromStaticFunction(bioRecv));
  }

  @:unreflective
  static function bioSend(p:Star<cpp.Void>, buf:ConstStar<UInt8>, len:SizeT):Int {
    final self:CppTlsSession = untyped __cpp__('(hx::Object*){0}', p);
    final n:Int = cast len;
    final bytes = Bytes.alloc(n);
    untyped __cpp__('memcpy((char*){0}->GetBase(), {1}, {2})', bytes.getData(), buf, n);
    self.netOut.addBytes(bytes, 0, n);
    return n;
  }

  @:unreflective
  static function bioRecv(p:Star<cpp.Void>, buf:Star<UInt8>, len:SizeT):Int {
    final self:CppTlsSession = untyped __cpp__('(hx::Object*){0}', p);
    final available = self.netIn.length - self.netInPos;
    if (available <= 0)
      return NativeTls.wantRead();
    final max:Int = cast len;
    final n = available > max ? max : available;
    untyped __cpp__('memcpy({0}, (char*){1}->GetBase() + {2}, {3})', buf, self.netIn.getData(), self.netInPos, n);
    self.netInPos += n;
    if (self.netInPos >= self.netIn.length) {
      self.netIn = Bytes.alloc(0);
      self.netInPos = 0;
    }
    return n;
  }

  public function handshake():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      pumpHandshake(() -> resolve(Noise), e -> reject(e));
      return null;
    });
  }

  public function read(cb:Callback<Outcome<Null<Chunk>, Error>>):Void {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    pumpRead(cb);
  }

  public function write(chunk:Chunk, cb:Callback<Outcome<Noise, Error>>):Void {
    if (chunk.length == 0) {
      cb.invoke(Success(Noise));
      return;
    }
    if (closed) {
      cb.invoke(Failure(tlsError('TLS connection closed')));
      return;
    }
    writeBytes(chunk.toBytes(), 0, chunk.length, cb);
  }

  public function shutdown(cb:Callback<Outcome<Noise, Error>>):Void {
    if (closed) {
      cb.invoke(Success(Noise));
      return;
    }
    pumpShutdown(cb);
  }

  function pumpHandshake(onDone:Void->Void, onFail:Error->Void) {
    if (closed)
      return;
    final r = NativeTls.sslHandshake(context);
    if (r == 0)
      flushNetOut(onDone);
    else if (r == NativeTls.wantRead())
      flushNetOut(() -> ensureNetRead(() -> pumpHandshake(onDone, onFail)));
    else if (r == NativeTls.wantWrite())
      flushNetOut(() -> pumpHandshake(onDone, onFail));
    else
      onFail(tlsError('TLS handshake failed: ${Mbedtls.errorString(r)}', r));
  }

  function pumpRead(cb:Callback<Outcome<Null<Chunk>, Error>>) {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    final buf = Bytes.alloc(0x4000);
    final ptr:Star<UInt8> = untyped __cpp__('(unsigned char*){0}->GetBase()', buf.getData());
    final r = NativeTls.sslRead(context, ptr, cast buf.length);
    if (r > 0)
      flushNetOut(() -> cb.invoke(Success(buf.sub(0, r))));
    else if (r == 0)
      flushNetOut(() -> cb.invoke(Success(null)));
    else if (r == NativeTls.wantRead())
      flushNetOut(() -> ensureNetRead(() -> if (closed) cb.invoke(Success(null)) else pumpRead(cb)));
    else if (r == NativeTls.wantWrite())
      flushNetOut(() -> pumpRead(cb));
    else if (r == NativeTls.peerCloseNotify()) {
      closed = true;
      flushNetOut(() -> cb.invoke(Success(null)));
    } else
      cb.invoke(Failure(tlsError('TLS read failed: ${Mbedtls.errorString(r)}', r)));
  }

  function writeBytes(data:Bytes, offset:Int, remaining:Int, cb:Callback<Outcome<Noise, Error>>) {
    if (remaining <= 0) {
      flushNetOut(() -> cb.invoke(Success(Noise)));
      return;
    }
    final ptr:ConstStar<UInt8> = untyped __cpp__('(const unsigned char*){0}->GetBase() + {1}', data.getData(), offset);
    final r = NativeTls.sslWrite(context, ptr, cast remaining);
    if (r > 0)
      flushNetOut(() -> writeBytes(data, offset + r, remaining - r, cb));
    else if (r == NativeTls.wantRead())
      flushNetOut(() -> ensureNetRead(() -> writeBytes(data, offset, remaining, cb)));
    else if (r == NativeTls.wantWrite())
      flushNetOut(() -> writeBytes(data, offset, remaining, cb));
    else
      cb.invoke(Failure(tlsError('TLS write failed: ${Mbedtls.errorString(r)}', r)));
  }

  function pumpShutdown(cb:Callback<Outcome<Noise, Error>>) {
    closed = true;
    flushNetOut(() -> {
      final shutdownReq = new Shutdown();
      final ctx:TlsShutdownCtx = {session: this, cb: cb};
      shutdownReq.setData(ctx);
      final status = stream.shutdown(shutdownReq, Callable.fromStaticFunction(onTlsShutdown));
      if (status != 0)
        cb.invoke(Failure(tlsError('TLS shutdown failed', status)));
    });
  }

  @:unreflective
  static function onTlsShutdown(req:Star<UvShutdown>, status:Int) {
    final shutdownReq:Shutdown = Native.shutdown(req);
    final ctx:TlsShutdownCtx = shutdownReq.getData();
    if (status != 0)
      ctx.cb.invoke(Failure(Error.withData('TLS shutdown failed', status)));
    else
      ctx.cb.invoke(Success(Noise));
  }

  function appendNetIn(data:Bytes) {
    if (netInPos > 0 && netInPos < netIn.length) {
      netIn = netIn.sub(netInPos, netIn.length - netInPos);
      netInPos = 0;
    }
    if (netIn.length == 0) {
      netIn = data;
      netInPos = 0;
    } else {
      final merged = Bytes.alloc(netIn.length + data.length);
      merged.blit(0, netIn, 0, netIn.length);
      merged.blit(netIn.length, data, 0, data.length);
      netIn = merged;
      netInPos = 0;
    }
  }

  function ensureNetRead(done:Void->Void) {
    if (netIn.length > netInPos) {
      done();
      return;
    }
    readWaiters.push(done);
    if (!readActive) {
      readActive = true;
      startNetRead();
    }
  }

  function startNetRead() {
    if (closed) {
      finishNetRead();
      return;
    }
    stream.readStart(Callable.fromStaticFunction(onTlsAlloc), Callable.fromStaticFunction(onTlsRead));
  }

  @:unreflective
  static function onTlsAlloc(handle:Star<UvHandle>, suggestedSize:SizeT, buf:Star<Buf_t>) {
    final size:Int = cast suggestedSize;
    buf.base = untyped __cpp__('(char*){0}', Stdlib.nativeMalloc(size));
    buf.len = cast size;
  }

  @:unreflective
  static function onTlsRead(handle:Star<UvStream>, nread:SSizeT, buf:ConstStar<Buf_t>) {
    final n:Int = cast nread;
    final s:Stream = Native.stream(handle);
    final self:CppTlsSession = s.asHandle().getData();
    if (self == null) {
      Buf.unmanaged(buf).free();
      return;
    }
    if (n > 0) {
      final out = Bytes.alloc(n);
      Buf.unmanaged(buf).copyToBytes(out, n);
      self.appendNetIn(out);
      self.finishNetRead();
    }
    if (n < 0) {
      self.closed = true;
      self.finishNetRead();
    }
    Buf.unmanaged(buf).free();
  }

  function finishNetRead() {
    if (readActive) {
      stream.readStop();
      readActive = false;
    }
    final waiters = readWaiters;
    readWaiters = [];
    for (w in waiters)
      w();
  }

  function flushNetOut(done:Void->Void) {
    if (netOut.length == 0) {
      done();
      return;
    }
    if (writeActive) {
      writeWaiter = done;
      return;
    }
    writeActive = true;
    writeNetOut(done);
  }

  function writeNetOut(done:Void->Void) {
    if (netOut.length == 0) {
      writeActive = false;
      final waiter = writeWaiter;
      writeWaiter = null;
      done();
      if (waiter != null)
        waiter();
      return;
    }
    final bytes = netOut.getBytes();
    netOut = new haxe.io.BytesBuffer();
    final writeReq = new Write();
    final writeBuf = new Buf();
    writeBuf.alloc(bytes.length);
    writeBuf.copyFromBytes(bytes, bytes.length);
    final wctx:TlsWriteCtx = {session: this, buf: writeBuf, done: done};
    writeReq.setData(wctx);
    final status = stream.write(writeReq, writeBuf, 1, Callable.fromStaticFunction(onTlsWrite));
    if (status != 0) {
      writeBuf.freeBase();
      writeActive = false;
      done();
    }
  }

  @:unreflective
  static function onTlsWrite(req:Star<UvWrite>, status:Int) {
    final writeReq:Write = Native.write(req);
    final ctx:TlsWriteCtx = writeReq.getData();
    ctx.buf.freeBase();
    if (status != 0) {
      ctx.session.writeActive = false;
      ctx.done();
      return;
    }
    ctx.session.writeNetOut(ctx.done);
  }

  function tlsError(message:String, ?code:Int) {
    return Error.withData(message, code);
  }
}
#end
