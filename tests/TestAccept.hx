package;

import tink.Chunk;
import tink.streams.IdealStream;
import tink.io.PipeResult;
import tink.tcp.*;
import tink.tcp.nodejs.*;

using tink.CoreApi;
using tink.streams.Stream;
using tink.io.Sink;
using tink.io.Source;

@:asserts
class TestAccept {
  
  public function new() {}
  
  @:describe('Accept a connection')
  public function accept() {
    var port = Future.trigger();
    
    NodejsAcceptor.inst.bind().handle(function(o) switch o {
      case Success(openPort):
        port.trigger(openPort.port);
        openPort.setHandler(function(i:Incoming):Outgoing {
          var chunk = Chunk.EMPTY;
          var stream = i.stream.chunked()
            .forEach(function(c) {
              chunk = chunk & c;
              return if(chunk.length < 5) Resume else Finish;
            })
            .map(function(c):IdealSource return switch c {
              case Halted(_):
                'Hello, ' + chunk.toString() + '!';
              case Depleted:
                asserts.fail('Unexpected depletion');
                'Unexpected depletion';
              case Failed(e):
                asserts.fail(e);
                e.toString();
            });
            
          return {
            stream: stream,
            allowHalfOpen: true
          }
        });
      case Failure(e):
        asserts.fail(e);
    });
    
    port.handle(function(port) {
      NodejsConnector.connect({host: 'localhost', port: port}, function(i:Incoming):Outgoing {
        i.stream.all().handle(function(o) switch o {
          case Success(chunk): asserts.assert(chunk == 'Hello, World!');
          case Failure(e): asserts.fail(e);
        });
        return {
          stream: 'World',
          allowHalfOpen: true
        }
      }).handle(function(p) {
        asserts.assert(p.isSuccess());
        asserts.done();
      });
    });
    
    return asserts;
  }
  
}

