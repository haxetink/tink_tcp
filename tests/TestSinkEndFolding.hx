package;

import tink.Chunk;
import tink.tcp.internal.DuplexSink;
import tink.tcp.internal.DuplexStream;
import tink.tcp.internal.TlsSession;
import tink.tcp.Endpoint;

using tink.io.Source;
using tink.CoreApi;

/**
 * E2 proof: end Failure must surface on the Future returned by
 * `consume` / `pipeTo` (not fire-and-forget). Used as acceptance for
 * ERROR_HANDLING_ROADMAP E2; V1 may rely on the same visibility.
 */
@:asserts
class TestSinkEndFolding {
  public function new() {}

  @:describe('E2: DuplexSink end Failure is visible on pipeTo Future')
  public function duplexEndFailure() {
    final sink = DuplexSink.wrap('fail-end', new FailEndDuplex());
    return (('hello' : IdealSource).pipeTo(sink, {end: true})).map(r -> {
      switch r {
        case SinkFailed(e, _):
          asserts.assert(e.message == 'end failed');
        case other:
          asserts.assert(false, 'expected SinkFailed, got $other');
      }
      return asserts.done();
    });
  }

  @:describe('E2: DuplexSink body failure is kept; end is not run')
  public function duplexBodyFailureWins() {
    final duplex = new FailWriteThenEndDuplex();
    final sink = DuplexSink.wrap('fail-write', duplex);
    return (('hello' : IdealSource).pipeTo(sink, {end: true})).map(r -> {
      asserts.assert(!duplex.endCalled);
      switch r {
        case SinkFailed(e, _):
          asserts.assert(e.message == 'write failed');
        case other:
          asserts.assert(false, 'expected SinkFailed, got $other');
      }
      return asserts.done();
    });
  }

  @:describe('E2: DuplexSink Success(false) from end does not fail the pipe')
  public function duplexEndAlreadyEndedOk() {
    final sink = DuplexSink.wrap('already-ended', new AlreadyEndedDuplex());
    return (('hello' : IdealSource).pipeTo(sink, {end: true})).map(r -> {
      switch r {
        case AllWritten:
          asserts.assert(true);
        case other:
          asserts.assert(false, 'expected AllWritten, got $other');
      }
      return asserts.done();
    });
  }

  @:describe('E2: DuplexSink end Failure (TlsSession) is visible on pipeTo Future')
  public function tlsEndFailure() {
    final sink = DuplexSink.wrap('fail-end-session', new FailEndSession());
    return (('hello' : IdealSource).pipeTo(sink, {end: true})).map(r -> {
      switch r {
        case SinkFailed(e, _):
          asserts.assert(e.message == 'end failed');
        case other:
          asserts.assert(false, 'expected SinkFailed, got $other');
      }
      return asserts.done();
    });
  }
}

private class FailEndDuplex implements DuplexStream {
  public function new() {}
  public function read():Promise<Null<Chunk>>
    return Promise.resolve(null);
  public function write(chunk:Chunk):Promise<Bool>
    return Promise.resolve(true);
  public function end():Promise<Bool>
    return Promise.reject(new Error('end failed'));
}

private class FailWriteThenEndDuplex implements DuplexStream {
  public var endCalled = false;
  public function new() {}
  public function read():Promise<Null<Chunk>>
    return Promise.resolve(null);
  public function write(chunk:Chunk):Promise<Bool>
    return Promise.reject(new Error('write failed'));
  public function end():Promise<Bool> {
    endCalled = true;
    return Promise.reject(new Error('end failed'));
  }
}

private class AlreadyEndedDuplex implements DuplexStream {
  public function new() {}
  public function read():Promise<Null<Chunk>>
    return Promise.resolve(null);
  public function write(chunk:Chunk):Promise<Bool>
    return Promise.resolve(true);
  public function end():Promise<Bool>
    return Promise.resolve(false);
}

/** Promise-shaped TlsSession mock whose `end` fails (ex-FailShutdownSession). */
private class FailEndSession implements TlsSession {
  public function new() {}
  public function handshake():Promise<Noise>
    return Promise.NOISE;
  public function read():Promise<Null<Chunk>>
    return Promise.resolve(null);
  public function write(chunk:Chunk):Promise<Bool>
    return Promise.resolve(true);
  public function end():Promise<Bool>
    return Promise.reject(new Error('end failed'));
  public function abort():Void {}
  public function getLocalEndpoint():Endpoint
    return {host: '?', port: 0};
  public function getPeerEndpoint():Endpoint
    return {host: '?', port: 0};
}
