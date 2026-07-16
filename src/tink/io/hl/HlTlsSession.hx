#if hl
package tink.io.hl;

import haxe.io.Bytes;
import hl.uv.Stream;
import sys.ssl.Context;
import tink.Chunk;
import tink.tcp.tls.TlsContext;
using tink.CoreApi;

@:allow(tink.io.hl)
class HlTlsSession implements tink.io.TlsSession {
  public final stream:Stream;
  final ssl:Context;
  /** Keeps TlsContext (and cert roots) alive for the session. */
  final context:TlsContext;

  var netIn = Bytes.alloc(0);
  var netInPos = 0;
  var netOut = new haxe.io.BytesBuffer();

  var readActive = false;
  var writeActive = false;
  var closed = false;
  var readWaiters:Array<Void->Void> = [];
  var writeWaiter:Null<Void->Void>;

  var bio:hl.NativeArray<Dynamic>;

  public function new(context:TlsContext, stream:Stream) {
    this.stream = stream;
    this.context = context;
    this.ssl = context.newSsl();

    bio = new hl.NativeArray(3);
    bio[0] = this;
    bio[1] = staticBioRead;
    bio[2] = staticBioWrite;
    ssl.setBio(bio);
  }

  static function staticBioRead(s:HlTlsSession, buf:hl.Bytes, len:Int):Int {
    return s.bioRecv(buf, len);
  }

  static function staticBioWrite(s:HlTlsSession, buf:hl.Bytes, len:Int):Int {
    return s.bioSend(buf, len);
  }

  public function handshake():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      pumpHandshake(() -> resolve(Noise), e -> reject(e));
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

  function pumpShutdown(cb:Callback<Outcome<Noise, tink.core.Error>>) {
    closed = true;
    flushNetOut(() -> {
      final handle = stream.handle;
      if (handle == null) {
        stream.close(() -> cb.invoke(Success(Noise)));
        return;
      }
      final ok = tink.tcp.hl.UvExtras.shutdown(handle, () -> {
        stream.close(() -> cb.invoke(Success(Noise)));
      });
      if (!ok)
        stream.close(() -> cb.invoke(Success(Noise)));
    });
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
    if (r == 0) {
      flushNetOut(onDone);
    } else if (r == -1) {
      final hadOut = netOut.length > 0;
      flushNetOut(() -> {
        if (hadOut)
          pumpHandshake(onDone, onFail);
        else
          ensureNetRead(() -> pumpHandshake(onDone, onFail));
      });
    } else {
      onFail(tlsError('TLS handshake failed'));
    }
  }

  function pumpRead(cb:Callback<Outcome<Null<Chunk>, tink.core.Error>>) {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    final buf = Bytes.alloc(0x4000);
    final r = ssl.recv(buf, 0, buf.length);
    if (r > 0) {
      flushNetOut(() -> cb.invoke(Success(buf.sub(0, r))));
    } else if (r == 0) {
      closed = true;
      flushNetOut(() -> cb.invoke(Success(null)));
    } else if (r == -1) {
      final hadOut = netOut.length > 0;
      flushNetOut(() -> {
        if (hadOut)
          pumpRead(cb);
        else
          ensureNetRead(() -> if (closed) cb.invoke(Success(null)) else pumpRead(cb));
      });
    } else {
      cb.invoke(Failure(tlsError('TLS read failed')));
    }
  }

  function writeBytes(data:Bytes, offset:Int, remaining:Int, cb:Callback<Outcome<Noise, tink.core.Error>>) {
    if (remaining <= 0) {
      flushNetOut(() -> cb.invoke(Success(Noise)));
      return;
    }
    final r = ssl.send(data, offset, remaining);
    if (r > 0) {
      flushNetOut(() -> writeBytes(data, offset + r, remaining - r, cb));
    } else if (r == -1) {
      final hadOut = netOut.length > 0;
      flushNetOut(() -> {
        if (hadOut)
          writeBytes(data, offset, remaining, cb);
        else
          ensureNetRead(() -> writeBytes(data, offset, remaining, cb));
      });
    } else {
      cb.invoke(Failure(tlsError('TLS write failed')));
    }
  }

  function bioSend(buf:hl.Bytes, len:Int):Int {
    netOut.addBytes(buf.toBytes(len), 0, len);
    return len;
  }

  function bioRecv(buf:hl.Bytes, len:Int):Int {
    final available = netIn.length - netInPos;
    if (available <= 0)
      return -2; // WANT_READ for HL ssl_set_bio
    final n = available > len ? len : available;
    buf.blit(0, netIn, netInPos, n);
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
    stream.readStartRaw(function(b:hl.Bytes, len:Int) {
      if (len < 0) {
        closed = true;
        finishNetRead();
        return;
      }
      if (len == 0)
        return;
      // uv frees the read buffer after this callback; copy immediately.
      final raw = b.toBytes(len);
      final copy = Bytes.alloc(len);
      copy.blit(0, raw, 0, len);
      appendNetIn(copy);
      finishNetRead();
    });
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
    stream.write(bytes, ok -> {
      if (!ok) {
        writeActive = false;
        done();
        return;
      }
      writeNetOut(done);
    }, 0, bytes.length);
  }

  function tlsError(message:String) {
    return tink.core.Error.withData(message, null);
  }
}
#end
