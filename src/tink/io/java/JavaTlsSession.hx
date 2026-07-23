#if java
package tink.io.java;

import java.lang.Integer;
import java.lang.Throwable;
import java.nio.ByteBuffer;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import haxe.io.Bytes;
import tink.Chunk;
import tink.tcp.tls.TlsConfig;
import tink.tcp.tls.TlsContext;

using tink.CoreApi;

@:allow(tink.io.java)
class JavaTlsSession {
  static final emptyApp = ByteBuffer.allocate(0);

  public final channel:AsynchronousSocketChannel;
  final context:TlsContext;
  /** Keeps TlsConfig (and SSLContext) alive for the session. */
  final config:TlsConfig;
  final executor:java.util.concurrent.ExecutorService;
  var netIn:ByteBuffer;
  var netOut:ByteBuffer;
  var appIn:ByteBuffer;
  var closed = false;
  var aborted = false;
  var pendingFails:Array<Void->Void> = [];

  public function new(config:TlsConfig, channel:AsynchronousSocketChannel, ?host:String, ?port:Int) {
    this.channel = channel;
    this.config = config;
    this.context = config.createContext(host, port);
    this.executor = java.util.concurrent.Executors.newSingleThreadExecutor();
    final packetSize = context.getSession().getPacketBufferSize();
    final appSize = context.getSession().getApplicationBufferSize();
    netIn = ByteBuffer.allocate(packetSize);
    netIn.limit(0);
    netOut = ByteBuffer.allocate(packetSize);
    appIn = ByteBuffer.allocate(appSize);
  }

  /** Idempotent hard-close: skip TLS shutdown, fail waiters, close channel. */
  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    closed = true;
    final fails = pendingFails;
    pendingFails = [];
    for (fail in fails)
      fail();
    try
      channel.close()
    catch (_:Dynamic) {}
    try
      executor.shutdownNow()
    catch (_:Dynamic) {}
  }

  public function handshake():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      final thread = new java.lang.Thread(new HandshakeRunnable(this, resolve, reject));
      thread.start();
      return null;
    });
  }

  public function read(cb:Callback<Outcome<Null<Chunk>, Error>>):Void {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    final once = onceRead(cb, Success(null));
    try
      executor.execute(new ExecutorRunnable(() -> {
        if (closed) {
          once.invoke(Success(null));
          return;
        }
        readOnEngine(once);
      }))
    catch (_:Dynamic)
      once.invoke(Success(null));
  }

  public function write(chunk:Chunk, cb:Callback<Outcome<Noise, Error>>):Void {
    if (chunk.length == 0) {
      cb.invoke(Success(Noise));
      return;
    }
    if (closed) {
      cb.invoke(Failure(abortedError()));
      return;
    }
    final once = onceWrite(cb, Failure(abortedError()));
    try
      executor.execute(new ExecutorRunnable(() -> {
        if (closed) {
          once.invoke(Failure(abortedError()));
          return;
        }
        writeOnEngine(chunk, once);
      }))
    catch (_:Dynamic)
      once.invoke(Failure(abortedError()));
  }

  public function shutdown(cb:Callback<Outcome<Noise, Error>>):Void {
    if (closed) {
      cb.invoke(Success(Noise));
      return;
    }
    final once = onceWrite(cb, Success(Noise));
    try
      executor.execute(new ExecutorRunnable(() -> {
        if (closed) {
          once.invoke(Success(Noise));
          return;
        }
        shutdownOnEngine(once);
      }))
    catch (_:Dynamic)
      once.invoke(Success(Noise));
  }

  function onceRead(
    cb:Callback<Outcome<Null<Chunk>, Error>>,
    onAbort:Outcome<Null<Chunk>, Error>
  ):Callback<Outcome<Null<Chunk>, Error>> {
    final done = new java.util.concurrent.atomic.AtomicBoolean(false);
    var fail:Void->Void = null;
    function finish(o:Outcome<Null<Chunk>, Error>) {
      if (done.compareAndSet(false, true)) {
        pendingFails.remove(fail);
        cb.invoke(o);
      }
    }
    fail = () -> finish(onAbort);
    pendingFails.push(fail);
    return finish;
  }

  function onceWrite(
    cb:Callback<Outcome<Noise, Error>>,
    onAbort:Outcome<Noise, Error>
  ):Callback<Outcome<Noise, Error>> {
    final done = new java.util.concurrent.atomic.AtomicBoolean(false);
    var fail:Void->Void = null;
    function finish(o:Outcome<Noise, Error>) {
      if (done.compareAndSet(false, true)) {
        pendingFails.remove(fail);
        cb.invoke(o);
      }
    }
    fail = () -> finish(onAbort);
    pendingFails.push(fail);
    return finish;
  }

  static inline function abortedError()
    return new Error('TLS connection aborted');

  function readOnEngine(cb:Callback<Outcome<Null<Chunk>, Error>>) {
    if (closed) {
      cb.invoke(Success(null));
      return;
    }
    try {
      while (true) {
        if (closed) {
          cb.invoke(Success(null));
          return;
        }
        if (netIn.position() >= netIn.limit()) {
          netRead(bytes -> {
            if (closed || bytes == -1)
              cb.invoke(Success(null));
            else
              try
                executor.execute(new ExecutorRunnable(() -> readOnEngine(cb)))
              catch (_:Dynamic)
                cb.invoke(Success(null));
          });
          return;
        }
        netIn.flip();
        appIn.clear();
        final result = context.unwrap(netIn, appIn);
        netIn.compact();
        switch Std.string(result.getStatus()) {
          case "BUFFER_UNDERFLOW":
            netRead(bytes -> {
              if (closed || bytes == -1)
                cb.invoke(Success(null));
              else
                try
                  executor.execute(new ExecutorRunnable(() -> readOnEngine(cb)))
                catch (_:Dynamic)
                  cb.invoke(Success(null));
            });
            return;
          case "BUFFER_OVERFLOW":
            appIn = enlarge(appIn);
            continue;
          case "CLOSED":
            cb.invoke(Success(null));
            return;
          default:
        }
        if (appIn.position() > 0) {
          appIn.flip();
          cb.invoke(Success(bufferToChunk(appIn)));
          return;
        }
        if (context.isInboundDone()) {
          cb.invoke(Success(null));
          return;
        }
      }
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function shutdownOnEngine(cb:Callback<Outcome<Noise, Error>>) {
    if (closed) {
      cb.invoke(Success(Noise));
      return;
    }
    try {
      if (!context.isOutboundDone())
        context.closeOutbound();
      flushCloseNotify(cb);
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function flushCloseNotify(cb:Callback<Outcome<Noise, Error>>) {
    if (closed) {
      cb.invoke(Success(Noise));
      return;
    }
    try {
      netOut.clear();
      final result = context.wrap(emptyApp, netOut);
      if (netOut.position() > 0) {
        netOut.flip();
        netWrite(netOut, () -> {
          if (closed) {
            cb.invoke(Success(Noise));
            return;
          }
          try
            executor.execute(new ExecutorRunnable(() -> flushCloseNotify(cb)))
          catch (_:Dynamic)
            cb.invoke(Success(Noise));
        });
        return;
      }
      cb.invoke(Success(Noise));
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function writeOnEngine(chunk:Chunk, cb:Callback<Outcome<Noise, Error>>) {
    writeChunkOnEngine(chunk.toBytes(), 0, chunk.length, cb);
  }

  function writeChunkOnEngine(data:Bytes, offset:Int, remaining:Int, cb:Callback<Outcome<Noise, Error>>) {
    if (closed) {
      cb.invoke(Failure(abortedError()));
      return;
    }
    try {
      if (remaining <= 0) {
        cb.invoke(Success(Noise));
        return;
      }
      final limit = Std.int(Math.min(remaining, context.getSession().getApplicationBufferSize()));
      final appBuf = ByteBuffer.wrap(data.getData(), offset, limit);
      netOut.clear();
      final result = context.wrap(appBuf, netOut);
      switch Std.string(result.getStatus()) {
        case "BUFFER_OVERFLOW":
          netOut = enlarge(netOut);
          writeChunkOnEngine(data, offset, remaining, cb);
          return;
        case "CLOSED":
          throw "TLS connection closed during write";
        default:
      }
      netOut.flip();
      netWrite(netOut, () -> {
        if (closed) {
          cb.invoke(Failure(abortedError()));
          return;
        }
        final consumed = result.bytesConsumed();
        try
          executor.execute(new ExecutorRunnable(() -> writeChunkOnEngine(data, offset + consumed, remaining - consumed, cb)))
        catch (_:Dynamic)
          cb.invoke(Failure(abortedError()));
      });
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function netRead(done:Int->Void) {
    netIn.compact();
    if (netIn.position() >= netIn.limit())
      netIn.limit(netIn.capacity());
    channel.read(netIn, netIn, new NetReadHandler(done));
  }

  function netWrite(buf:ByteBuffer, done:Void->Void) {
    if (!buf.hasRemaining()) {
      done();
      return;
    }
    channel.write(buf, buf, new NetWriteHandler(channel, buf, done));
  }

  function blockingHandshake() {
    context.beginHandshake();
    var status = Std.string(context.getHandshakeStatus());
    while (true) {
      status = switch status {
        case "NEED_UNWRAP":
          blockingUnwrap();
        case "NEED_WRAP":
          blockingWrap();
        case "NEED_TASK":
          runDelegatedTasksSync();
          Std.string(context.getHandshakeStatus());
        case "FINISHED" | "NOT_HANDSHAKING":
          return;
        case other:
          throw 'Unexpected TLS handshake status: $other';
      };
    }
  }

  function blockingUnwrap():String {
    while (true) {
      if (netIn.position() >= netIn.limit())
        blockingNetRead();
      netIn.flip();
      appIn.clear();
      final result = context.unwrap(netIn, appIn);
      netIn.compact();
      final hs = Std.string(result.getHandshakeStatus());
      switch Std.string(result.getStatus()) {
        case "BUFFER_UNDERFLOW":
          blockingNetRead();
          continue;
        case "BUFFER_OVERFLOW":
          appIn = enlarge(appIn);
          continue;
        case "CLOSED":
          throw "TLS connection closed during unwrap";
        default:
      }
      switch hs {
        case "NEED_UNWRAP":
          continue;
        default:
          return hs;
      }
    }
  }

  function blockingWrap():String {
    while (true) {
      netOut.clear();
      final result = context.wrap(emptyApp, netOut);
      final hs = Std.string(result.getHandshakeStatus());
      switch Std.string(result.getStatus()) {
        case "BUFFER_OVERFLOW":
          netOut = enlarge(netOut);
          continue;
        case "CLOSED":
          throw "TLS connection closed during wrap";
        default:
      }
      netOut.flip();
      blockingNetWrite(netOut);
      switch hs {
        case "NEED_WRAP":
          continue;
        default:
          return hs;
      }
    }
  }

  function blockingNetRead() {
    final latch = new java.util.concurrent.CountDownLatch(1);
    final holder = new IoResult();
    netIn.compact();
    if (netIn.position() >= netIn.limit())
      netIn.limit(netIn.capacity());
    channel.read(netIn, netIn, new ReadAwaitHandler(latch, holder));
    latch.await();
    if (holder.error != null)
      throw holder.error;
    if (holder.bytes == -1)
      throw "TLS peer closed connection";
  }

  function blockingNetWrite(buf:ByteBuffer) {
    while (buf.hasRemaining()) {
      final latch = new java.util.concurrent.CountDownLatch(1);
      final holder = new IoResult();
      channel.write(buf, buf, new WriteAwaitHandler(latch, holder));
      latch.await();
      if (holder.error != null)
        throw holder.error;
    }
  }

  function runDelegatedTasksSync() {
    var task:java.lang.Runnable;
    while ((task = context.getDelegatedTask()) != null)
      task.run();
  }

  static function enlarge(buf:ByteBuffer):ByteBuffer {
    final bigger = ByteBuffer.allocate(buf.capacity() * 2);
    buf.flip();
    bigger.put(buf);
    return bigger;
  }

  static function bufferToChunk(buf:ByteBuffer):Chunk {
    final data = buf.array();
    final start = buf.arrayOffset() + buf.position();
    final len = buf.remaining();
    return Bytes.ofData(data).sub(start, len);
  }
}

class HandshakeRunnable implements java.lang.Runnable {
  final session:JavaTlsSession;
  final resolve:Noise->Void;
  final reject:Error->Void;

  public function new(session, resolve, reject) {
    this.session = session;
    this.resolve = resolve;
    this.reject = reject;
  }

  public function run() {
    try {
      session.blockingHandshake();
      OnMainThread.run(() -> resolve(Noise));
    } catch (e:Dynamic) {
      OnMainThread.run(() -> reject(Error.withData(Std.string(e), e)));
    }
  }
}

class NetReadHandler implements CompletionHandler<Integer, ByteBuffer> {
  final done:Int->Void;

  public function new(done) {
    this.done = done;
  }

  public function completed(result:Integer, attachment:ByteBuffer) {
    done(result.toInt());
  }

  public function failed(exc:Throwable, attachment:ByteBuffer) {
    done(-1);
  }
}

class NetWriteHandler implements CompletionHandler<Integer, ByteBuffer> {
  final channel:AsynchronousSocketChannel;
  final buf:ByteBuffer;
  final done:Void->Void;

  public function new(channel, buf, done) {
    this.channel = channel;
    this.buf = buf;
    this.done = done;
  }

  public function completed(result:Integer, attachment:ByteBuffer) {
    if (buf.hasRemaining())
      channel.write(buf, buf, this);
    else
      done();
  }

  public function failed(exc:Throwable, attachment:ByteBuffer) {
    done();
  }
}

class IoResult {
  public var bytes:Int = 0;
  public var error:Dynamic;

  public function new() {}
}

class ReadAwaitHandler implements CompletionHandler<Integer, ByteBuffer> {
  final latch:java.util.concurrent.CountDownLatch;
  final holder:IoResult;

  public function new(latch, holder) {
    this.latch = latch;
    this.holder = holder;
  }

  public function completed(result:Integer, attachment:ByteBuffer) {
    holder.bytes = result.toInt();
    latch.countDown();
  }

  public function failed(exc:Throwable, attachment:ByteBuffer) {
    holder.error = exc;
    latch.countDown();
  }
}

class WriteAwaitHandler implements CompletionHandler<Integer, ByteBuffer> {
  final latch:java.util.concurrent.CountDownLatch;
  final holder:IoResult;

  public function new(latch, holder) {
    this.latch = latch;
    this.holder = holder;
  }

  public function completed(result:Integer, attachment:ByteBuffer) {
    holder.bytes = result.toInt();
    latch.countDown();
  }

  public function failed(exc:Throwable, attachment:ByteBuffer) {
    holder.error = exc;
    latch.countDown();
  }
}

class ExecutorRunnable implements java.lang.Runnable {
  final fn:Void->Void;

  public function new(fn) {
    this.fn = fn;
  }

  public function run() {
    fn();
  }
}
#end
