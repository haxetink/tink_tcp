#if eval
package tink.io.luv;

import eval.luv.*;
import tink.Chunk;
import tink.tcp.Endpoint;

using tink.CoreApi;
using eval.luv.Stream;
using eval.luv.Buffer;

typedef ReadOutcome = Outcome<Null<Chunk>, Error>;

class WrappedStream implements tink.io.TcpSession {
  final name:String;
  final stream:Tcp;
  final chunkSize:Int;

  var readActive = false;
  var readEnded = false;
  var readRetries = 0;
  var readWaiters:Array<Callback<ReadOutcome>> = [];
  var readQueue:Array<Chunk> = [];

  var writeEnded = false;
  var closed = false;

  public function new(name:String, stream:Tcp, ?chunkSize:Int = 0x10000) {
    this.name = name;
    this.stream = stream;
    this.chunkSize = chunkSize;
    Handle.ref(stream);
  }

  public function getLocalEndpoint():Endpoint {
    return switch stream.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
  }

  public function getPeerEndpoint():Endpoint {
    return switch stream.getPeerName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
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
    readRetries = 0;
    stream.readStart(result -> {
      switch result {
        case Error(UVError.UV_EOF):
          finishReading();
          completeWaiters(Success(null));
        case Error(UVError.UV_EAGAIN):
          return;
        case Error(UVError.UV_UNKNOWN):
          if (++readRetries < 8) {
            finishReading();
            startReading();
          } else {
            finishReading();
            completeWaiters(Failure(luvError(UVError.UV_UNKNOWN, 'Read failed for "$name"')));
          }
        case Error(e):
          finishReading();
          completeWaiters(Failure(luvError(e, 'Read failed for "$name"')));
        case Ok(buf):
          final chunk:Chunk = buf.toBytes();
          if (chunk.length == 0)
            return;
          if (readWaiters.length > 0) {
            final waiter = readWaiters.shift();
            waiter.invoke(Success(chunk));
          } else readQueue.push(chunk);
      }
    }, _ -> Buffer.create(chunkSize));
  }

  function finishReading() {
    if (readActive) {
      stream.readStop();
      readActive = false;
    }
  }

  function completeWaiters(result:ReadOutcome) {
    switch result {
      case Success(null):
        readEnded = true;
        tryClose();
      default:
    }
    while(readWaiters.length > 0)
      readWaiters.shift().invoke(result);
  }

  public function write(chunk:Chunk):Promise<Bool> {
    return Future.irreversible(cb -> {
      if (chunk.length == 0)
        cb(Success(true));
      else
        writeBuffer(Buffer.fromBytes(chunk.toBytes()), cb);
    });
  }

  function writeBuffer(buf:Buffer, cb:Callback<Outcome<Bool, Error>>) {
    stream.write([buf], (result, bytesWritten) -> {
      final size = buf.size();
      switch result {
        case Error(UVError.UV_EAGAIN):
          writeBuffer(buf, cb);
        case Error(e):
          if (bytesWritten > 0 && bytesWritten < size) writeBuffer(buf.sub(bytesWritten, size - bytesWritten), cb); else
            cb.invoke(Failure(luvError(e, 'Write failed for "$name"')));
        case Ok(_):
          if (bytesWritten >= size) cb.invoke(Success(true)); else writeBuffer(buf.sub(bytesWritten, size - bytesWritten), cb);
      }
    });
  }

  public function end():Promise<Bool> {
    return Future.irreversible(cb -> {
      if (writeEnded)
        cb(Success(false));
      else
        stream.shutdown(result -> {
          switch result {
            case Error(e):
              cb(Failure(luvError(e, 'Shutdown failed for "$name"')));
            case Ok(_):
              writeEnded = true;
              tryClose();
              cb(Success(false));
          }
        });
    });
  }

  /**
    Best-effort hard-close: fail/end pending waiters, mark both sides ended so later
    `end()` is a no-op, then close the handle without UV `shutdown()`.
  **/
  public function abort():Void {
    if (closed)
      return;
    writeEnded = true;
    readEnded = true;
    finishReading();
    while (readWaiters.length > 0)
      readWaiters.shift().invoke(Failure(new Error('Stream "$name" aborted')));
    readQueue = [];
    doClose();
    closed = true;
  }

  function tryClose() {
    if (!closed && readEnded && writeEnded)
      doClose();
  }

  function doClose() {
    if (!closed && !Handle.isClosing(stream)) {
      closed = true;
      finishReading();
      Handle.close(stream, noop);
    }
  }

  static function luvError(e:UVError, message:String):Error {
    return Error.withData('$message: ${e.toString()}', e);
  }

  static function noop() {}
}
#end
