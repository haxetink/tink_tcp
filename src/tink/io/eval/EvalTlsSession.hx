#if eval
package tink.io.eval;

import eval.luv.*;
import haxe.io.Bytes;
import mbedtls.Error as MbedtlsError;
import mbedtls.Ssl;
import tink.Chunk;
import tink.tcp.tls.eval.EvalTlsContext;

using tink.CoreApi;
using eval.luv.Buffer;
using eval.luv.Stream;

@:allow(tink.io.eval)
class EvalTlsSession implements tink.io.TlsSession {
  public final tcp:Tcp;
  final ssl:Ssl;
  final ctx:EvalTlsContext;

  var netIn = Bytes.alloc(0);
  var netInPos = 0;
  var netOut = new haxe.io.BytesBuffer();

  var readActive = false;
  var writeActive = false;
  var closed = false;
  var readWaiters:Array<Void->Void> = [];
  var writeWaiter:Null<Void->Void>;

  public function new(tcp:Tcp, ssl:Ssl, ctx:EvalTlsContext) {
    this.tcp = tcp;
    this.ssl = ssl;
    this.ctx = ctx;
    Handle.ref(tcp);
    ssl.set_bio(bioSend, bioRecv);
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

  public function read(cb:Callback<Outcome<Null<Chunk>, tink.core.Error>>):Void {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    pumpRead(cb);
  }

  public function write(chunk:Chunk, cb:Callback<Outcome<Noise, tink.core.Error>>):Void {
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

  public function shutdown(cb:Callback<Outcome<Noise, tink.core.Error>>):Void {
    if (closed) {
      cb.invoke(Success(Noise));
      return;
    }
    pumpShutdown(cb);
  }

  function pumpHandshake(onDone:Void->Void, onFail:tink.core.Error->Void) {
    if (closed)
      return;
    final r = ssl.handshake();
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
    final r = ssl.read(buf, 0, buf.length);
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

  function writeBytes(data:Bytes, offset:Int, remaining:Int, cb:Callback<Outcome<Noise, tink.core.Error>>) {
    if (remaining <= 0) {
      flushNetOut(() -> cb.invoke(Success(Noise)));
      return;
    }
    final r = ssl.write(data, offset, remaining);
    if (r > 0)
      flushNetOut(() -> writeBytes(data, offset + r, remaining - r, cb));
    else if (r == MbedtlsError.WANT_READ)
      flushNetOut(() -> ensureNetRead(() -> writeBytes(data, offset, remaining, cb)));
    else if (r == MbedtlsError.WANT_WRITE)
      flushNetOut(() -> writeBytes(data, offset, remaining, cb));
    else
      cb.invoke(Failure(tlsError('TLS write failed: ${MbedtlsError.strerror(r)}', r)));
  }

  function pumpShutdown(cb:Callback<Outcome<Noise, tink.core.Error>>) {
    closed = true;
    flushNetOut(() -> {
      tcp.shutdown(result -> {
        switch result {
          case Error(e):
            cb.invoke(Failure(tlsError('TLS shutdown failed: ${e}')));
          case Ok(_):
            cb.invoke(Success(Noise));
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
}
#end
