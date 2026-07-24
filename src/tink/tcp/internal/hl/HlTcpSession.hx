#if hl
package tink.tcp.internal.hl;

import hl.uv.Stream;
import haxe.io.Bytes;
import tink.Chunk;
import tink.tcp.Endpoint;

using tink.CoreApi;

typedef HlReadOutcome = Outcome<Null<Chunk>, Error>;

class HlTcpSession implements tink.tcp.internal.TcpSession {
  final name:String;
  final stream:Stream;
  final chunkSize:Int;
  final local:Endpoint;
  final peer:Endpoint;

  var readActive = false;
  var readEnded = false;
  var readWaiters:Array<Callback<HlReadOutcome>> = [];
  var readQueue:Array<Chunk> = [];

  var writeEnded = false;
  var closed = false;

  public function new(name:String, stream:Stream, ?chunkSize:Int = 0x10000, ?local:Endpoint, ?peer:Endpoint) {
    this.name = name;
    this.stream = stream;
    this.chunkSize = chunkSize;
    this.local = local ?? {host: '?', port: 0};
    this.peer = peer ?? {host: '?', port: 0};
  }

  public function getLocalEndpoint():Endpoint
    return local;

  public function getPeerEndpoint():Endpoint
    return peer;

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
    stream.readStartRaw(function(b:hl.Bytes, len:Int) {
      if (len < 0) {
        finishReading();
        completeWaiters(Success(null));
        return;
      }
      if (len == 0)
        return;
      // uv frees the read buffer after this callback; copy immediately.
      final raw = b.toBytes(len);
      final copy = Bytes.alloc(len);
      copy.blit(0, raw, 0, len);
      final chunk:Chunk = copy;
      if (readWaiters.length > 0) {
        final waiter = readWaiters.shift();
        waiter.invoke(Success(chunk));
      } else
        readQueue.push(chunk);
    });
  }

  function finishReading() {
    if (readActive) {
      stream.readStop();
      readActive = false;
    }
  }

  function completeWaiters(result:HlReadOutcome) {
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
      if (writeEnded || closed) {
        cb(Failure(new Error('Write failed for "$name"')));
      } else if (chunk.length == 0)
        cb(Success(true));
      else {
        final bytes = chunk.toBytes();
        stream.write(bytes, ok -> {
          if (ok)
            cb(Success(true));
          else
            cb(Failure(new Error('Write failed for "$name"')));
        }, 0, bytes.length);
      }
    });
  }

  public function end():Promise<Bool> {
    return Future.irreversible(cb -> {
      if (writeEnded) {
        cb(Success(false));
      } else {
        writeEnded = true;
        final handle = stream.handle;
        if (handle == null) {
          tryClose();
          cb(Success(false));
        } else {
          final ok = tink.tcp.hl.UvExtras.shutdown(handle, () -> {
            tryClose();
            cb(Success(false));
          });
          if (!ok) {
            // Fallback when native shutdown is unavailable: full close.
            doClose();
            cb(Success(false));
          }
        }
      }
    });
  }

  /**
    Best-effort hard-close: end pending read waiters, mark both sides ended so a later
    `end()` / UV shutdown is skipped, then `doClose()` (no graceful FIN).
  **/
  public function abort():Void {
    writeEnded = true;
    finishReading();
    readEnded = true;
    while (readWaiters.length > 0)
      readWaiters.shift().invoke(Success(null));
    doClose();
  }

  function tryClose() {
    if (!closed && readEnded && writeEnded)
      doClose();
  }

  function doClose() {
    if (!closed) {
      closed = true;
      finishReading();
      stream.close();
    }
  }

  public function close() {
    doClose();
  }
}
#end
