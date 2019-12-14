package;

import tink.io.*;
import tink.io.PipeResult;
import tink.tcp.*;

using StringTools;
using tink.io.Source;
using tink.CoreApi;

@:asserts
class TestConnect {
  
  public function new() {}
  
  @:describe('Read from a web server')
  #if (((haxe_ver > 3.210) || nodejs) && !java)
  @:variant('https' ('encrypted.google.com', 443))
  #end
  @:variant('http' ('httpbin.org', 80))
  @:include
  public function connect(host:String, port:Int) {
    
    var pipeResult = Future.trigger();
    var connectResult = Future.trigger();
    
    Future.ofMany([pipeResult.asFuture(), connectResult.asFuture()]).handle(function(v) asserts.done());
    
    #if java tink.tcp.java.JavaConnector #elseif nodejs tink.tcp.nodejs.NodejsConnector #end
    .connect({host: host, port: port}, function(i:Incoming):Outgoing {
      i.stream.all().handle(function(o) switch o {
        case Success(chunk):
          asserts.assert(chunk.length > 0);
          asserts.assert(chunk.toString().startsWith('HTTP')); // make sure we got an HTTP response
          pipeResult.trigger(Noise);
        case Failure(e):
          asserts.fail(e);
      });
      return {
        stream: 'GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
        allowHalfOpen: true
      }
    }).handle(function(p) {
      asserts.assert(p.isSuccess());
      connectResult.trigger(Noise);
    });
    
    return asserts;
  }
  
}

