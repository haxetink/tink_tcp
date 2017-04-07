package;

import tink.io.*;
import tink.io.PipeResult;
import tink.tcp.*;
import tink.tcp.nodejs.*;
using tink.CoreApi;

@:asserts
class TestConnect {
  
  public function new() {}
  
  @:describe('Read from a web server')
  #if ((haxe_ver > 3.210) || nodejs)
  @:variant('https' ('encrypted.google.com', 443))
  #end
  @:variant('http' ('www.example.com', 80))
  public function connect(host:String, port:Int) {
    
    NodejsConnector.connect({host: host, port: port}, function(i:Incoming):Outgoing {
      i.stream.pipeTo(Sink.BLACKHOLE).handle(function(o) asserts.assert(o == AllWritten));
      return {
        stream: 'GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
        allowHalfOpen: true
      }
    }).handle(function(p) {
      asserts.assert(p.isSuccess());
      asserts.done();
    });
    
    return asserts;
  }
  
}

