#if java
package tink.io.java;

import java.lang.Integer;
import java.lang.Throwable;
import java.nio.ByteBuffer;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import haxe.io.Bytes;
import tink.Chunk;

using tink.CoreApi;

@:allow(tink.io.java)
class JavaTlsSession {
  static final emptyApp = ByteBuffer.allocate(0);

  public final channel:AsynchronousSocketChannel;
  final engine:java.javax.net.ssl.SSLEngine;
  final executor:java.util.concurrent.ExecutorService;
  var netIn:ByteBuffer;
  var netOut:ByteBuffer;
  var appIn:ByteBuffer;

  public function new(channel:AsynchronousSocketChannel, engine:java.javax.net.ssl.SSLEngine) {
    this.channel = channel;
    this.engine = engine;
    this.executor = java.util.concurrent.Executors.newSingleThreadExecutor();
    final packetSize = engine.getSession().getPacketBufferSize();
    final appSize = engine.getSession().getApplicationBufferSize();
    netIn = ByteBuffer.allocate(packetSize);
    netIn.limit(0);
    netOut = ByteBuffer.allocate(packetSize);
    appIn = ByteBuffer.allocate(appSize);
  }

  public function handshake():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      final thread = new java.lang.Thread(new HandshakeRunnable(this, resolve, reject));
      thread.start();
      return null;
    });
  }

  public function read(cb:Callback<Outcome<Null<Chunk>, Error>>):Void {
    executor.execute(new ExecutorRunnable(() -> readOnEngine(cb)));
  }

  public function write(chunk:Chunk, cb:Callback<Outcome<Noise, Error>>):Void {
    if (chunk.length == 0) {
      cb.invoke(Success(Noise));
      return;
    }
    executor.execute(new ExecutorRunnable(() -> writeOnEngine(chunk, cb)));
  }

  public function shutdown(cb:Callback<Outcome<Noise, Error>>):Void {
    executor.execute(new ExecutorRunnable(() -> shutdownOnEngine(cb)));
  }

  function readOnEngine(cb:Callback<Outcome<Null<Chunk>, Error>>) {
    try {
      while (true) {
        if (netIn.position() >= netIn.limit()) {
          netRead(bytes -> {
            if (bytes == -1)
              cb.invoke(Success(null));
            else
              executor.execute(new ExecutorRunnable(() -> readOnEngine(cb)));
          });
          return;
        }
        netIn.flip();
        appIn.clear();
        final result = engine.unwrap(netIn, appIn);
        netIn.compact();
        switch Std.string(result.getStatus()) {
          case "BUFFER_UNDERFLOW":
            netRead(bytes -> {
              if (bytes == -1)
                cb.invoke(Success(null));
              else
                executor.execute(new ExecutorRunnable(() -> readOnEngine(cb)));
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
        if (engine.isInboundDone()) {
          cb.invoke(Success(null));
          return;
        }
      }
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function shutdownOnEngine(cb:Callback<Outcome<Noise, Error>>) {
    try {
      if (!engine.isOutboundDone())
        engine.closeOutbound();
      flushCloseNotify(cb);
    } catch (e:Dynamic) {
      cb.invoke(Failure(Error.withData(Std.string(e), e)));
    }
  }

  function flushCloseNotify(cb:Callback<Outcome<Noise, Error>>) {
    try {
      netOut.clear();
      final result = engine.wrap(emptyApp, netOut);
      if (netOut.position() > 0) {
        netOut.flip();
        netWrite(netOut, () -> executor.execute(new ExecutorRunnable(() -> flushCloseNotify(cb))));
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
    try {
      if (remaining <= 0) {
        cb.invoke(Success(Noise));
        return;
      }
      final limit = Std.int(Math.min(remaining, engine.getSession().getApplicationBufferSize()));
      final appBuf = ByteBuffer.wrap(data.getData(), offset, limit);
      netOut.clear();
      final result = engine.wrap(appBuf, netOut);
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
        final consumed = result.bytesConsumed();
        executor.execute(new ExecutorRunnable(() -> writeChunkOnEngine(data, offset + consumed, remaining - consumed, cb)));
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
    engine.beginHandshake();
    var status = Std.string(engine.getHandshakeStatus());
    while (true) {
      status = switch status {
        case "NEED_UNWRAP":
          blockingUnwrap();
        case "NEED_WRAP":
          blockingWrap();
        case "NEED_TASK":
          runDelegatedTasksSync();
          Std.string(engine.getHandshakeStatus());
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
      final result = engine.unwrap(netIn, appIn);
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
      final result = engine.wrap(emptyApp, netOut);
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
    while ((task = engine.getDelegatedTask()) != null)
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
