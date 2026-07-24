#if eval
package tink.io.eval;

import eval.luv.*;
import haxe.io.Bytes;
import mbedtls.Error as MbedtlsError;
import tink.Chunk;
import tink.tcp.Endpoint;
import tink.tcp.tls.TlsConfig;
import tink.tcp.tls.TlsContext;
using tink.CoreApi;
using eval.luv.Buffer;
using eval.luv.Stream;

@:allow(tink.io.eval)
class EvalTlsSession implements tink.io.TlsSession {
  public final tcp:Tcp;
  final context:TlsContext;
  /** Keeps TlsConfig (and entropy/drbg) alive for the session. */
  final config:TlsConfig;

  var netIn = Bytes.alloc(0);
  var netInPos = 0;
  var netOut = new haxe.io.BytesBuffer();

  var readActive = false;
  var writeActive = false;
  var closed = false;
  var aborted = false;
  var readWaiters:Array<Void->Void> = [];
  var writeWaiter:Null<Void->Void>;

  public function new(config:TlsConfig, tcp:Tcp) {
    this.tcp = tcp;
    this.config = config;
    this.context = config.createContext();
    Handle.ref(tcp);
    context.set_bio(bioSend, bioRecv);
  }

  public function handshake():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      pumpHandshake(
        () -> resolve(Noise),
        e -> reject(e)
      );
      return null;
    });
  }

  public function read():Promise<Null<Chunk>> {
    return Future.irreversible(cb -> {
      if (closed)
        cb(Success(null));
      else
        pumpRead(cb);
    });
  }

  public function write(chunk:Chunk):Promise<Bool> {
    return Future.irreversible(cb -> {
      if (chunk.length == 0)
        cb(Success(true));
      else if (closed)
        cb(Failure(tlsError('TLS connection closed')));
      else
        writeBytes(chunk.toBytes(), 0, chunk.length, cb);
    });
  }

  public function end():Promise<Bool> {
    return Future.irreversible(cb -> {
      if (closed)
        cb(Success(false));
      else
        pumpEnd(cb);
    });
  }

  /**
    Session-level force-abort: mark closed so later `end()` is a no-op,
    wake pending waiters, hard-close TCP without TLS close_notify / UV shutdown.
  **/
  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    closed = true;
    finishNetRead();
    writeActive = false;
    final waiter = writeWaiter;
    writeWaiter = null;
    if (waiter != null)
      waiter();
    if (!Handle.isClosing(tcp))
      Handle.close(tcp, noop);
  }

  public function getLocalEndpoint():Endpoint {
    return switch tcp.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
  }

  public function getPeerEndpoint():Endpoint {
    return switch tcp.getPeerName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
  }

  function pumpHandshake(onDone:Void->Void, onFail:tink.core.Error->Void) {
    if (closed)
      return;
    final r = context.handshake();
    if (r == 0)
      flushNetOut(onDone);
    else if (r == MbedtlsError.WANT_READ)
      flushNetOut(() -> ensureNetRead(() -> pumpHandshake(onDone, onFail)));
    else if (r == MbedtlsError.WANT_WRITE)
      flushNetOut(() -> pumpHandshake(onDone, onFail));
    else
      onFail(tlsError('TLS handshake failed: ${MbedtlsError.strerror(r)}', r));
  }

  function pumpRead(cb:Callback<Outcome<Null<Chunk>, tink.core.Error>>) {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    final buf = Bytes.alloc(0x4000);
    final r = context.read(buf, 0, buf.length);
    if (r > 0) {
      flushNetOut(() -> cb.invoke(Success(buf.sub(0, r))));
    } else if (r == 0) {
      flushNetOut(() -> cb.invoke(Success(null)));
    } else if (r == MbedtlsError.WANT_READ) {
      flushNetOut(() -> ensureNetRead(() -> if (closed) cb.invoke(Success(null)) else pumpRead(cb)));
    } else if (r == MbedtlsError.WANT_WRITE) {
      flushNetOut(() -> pumpRead(cb));
    } else if (r == MbedtlsError.PEER_CLOSE_NOTIFY) {
      closed = true;
      flushNetOut(() -> cb.invoke(Success(null)));
    } else {
      cb.invoke(Failure(tlsError('TLS read failed: ${MbedtlsError.strerror(r)}', r)));
    }
  }

  function writeBytes(data:Bytes, offset:Int, remaining:Int, cb:Callback<Outcome<Bool, tink.core.Error>>) {
    if (closed) {
      cb.invoke(Failure(tlsError('TLS connection closed')));
      return;
    }
    if (remaining <= 0) {
      flushNetOut(() -> cb.invoke(Success(true)));
      return;
    }
    final r = context.write(data, offset, remaining);
    if (r > 0)
      flushNetOut(() -> writeBytes(data, offset + r, remaining - r, cb));
    else if (r == MbedtlsError.WANT_READ)
      flushNetOut(() -> ensureNetRead(() -> if (closed) cb.invoke(Failure(tlsError('TLS connection closed'))) else writeBytes(data, offset, remaining, cb)));
    else if (r == MbedtlsError.WANT_WRITE)
      flushNetOut(() -> writeBytes(data, offset, remaining, cb));
    else
      cb.invoke(Failure(tlsError('TLS write failed: ${MbedtlsError.strerror(r)}', r)));
  }

  /** Graceful end: flush pending ciphertext, then TCP/UV shutdown. No mbedtls close_notify. */
  function pumpEnd(cb:Callback<Outcome<Bool, tink.core.Error>>) {
    closed = true;
    flushNetOut(() -> {
      tcp.shutdown(result -> {
        switch result {
          case Error(e):
            cb.invoke(Failure(tlsError('TLS end failed: ${e}')));
          case Ok(_):
            cb.invoke(Success(false));
        }
      });
    });
  }

  function bioSend(buf:Bytes, pos:Int, len:Int):Int {
    netOut.addBytes(buf, pos, len);
    return len;
  }

  function bioRecv(buf:Bytes, pos:Int, len:Int):Int {
    final available = netIn.length - netInPos;
    if (available <= 0)
      return MbedtlsError.WANT_READ;
    final n = available > len ? len : available;
    buf.blit(pos, netIn, netInPos, n);
    netInPos += n;
    if (netInPos >= netIn.length) {
      netIn = Bytes.alloc(0);
      netInPos = 0;
    }
    return n;
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
    tcp.readStart(result -> {
      switch result {
        case Error(UVError.UV_EOF):
          closed = true;
          finishNetRead();
        case Error(UVError.UV_EAGAIN):
        case Error(_):
          finishNetRead();
        case Ok(buf):
          final chunk = buf.toBytes();
          if (chunk.length > 0) {
            appendNetIn(chunk);
            finishNetRead();
          }
      }
    }, _ -> Buffer.create(0x4000));
  }

  function finishNetRead() {
    if (readActive) {
      tcp.readStop();
      readActive = false;
    }
    final waiters = readWaiters;
    readWaiters = [];
    for (w in waiters)
      w();
  }

  function flushNetOut(done:Void->Void) {
    if (aborted) {
      netOut = new haxe.io.BytesBuffer();
      done();
      return;
    }
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
    writeBuffer(Buffer.fromBytes(bytes), 0, done);
  }

  function writeBuffer(buf:Buffer, offset:Int, done:Void->Void) {
    final size = buf.size();
    if (offset >= size) {
      writeNetOut(done);
      return;
    }
    final slice = offset == 0 ? buf : buf.sub(offset, size - offset);
    tcp.write([slice], (result, bytesWritten) -> {
      switch result {
        case Error(UVError.UV_EAGAIN):
          writeBuffer(slice, 0, done);
        case Error(e):
          writeActive = false;
          done();
        case Ok(_):
          final next = offset + bytesWritten;
          if (next >= size)
            writeNetOut(done);
          else
            writeBuffer(buf, next, done);
      }
    });
  }

  function tlsError(message:String, ?code:Int) {
    return tink.core.Error.withData(message, code);
  }

  static function noop() {}
}
#end
