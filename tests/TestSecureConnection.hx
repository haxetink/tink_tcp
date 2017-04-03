package;

import haxe.io.*;
import tink.io.*;
import tink.io.Pipe;
import tink.tcp.*;
import tink.unit.*;
import tink.testrunner.*;
using StringTools;
using tink.CoreApi;

class TestSecureConnection {
  
  public function new() {}
  
  @:describe("Secure connection")
  public function test(asserts:AssertionBuffer) {
    Connection.tryEstablish({host:'encrypted.google.com', port:443}).handle(function(o) switch o {
      case Success(cnx):
        ([
            "GET /",
            "Host: www.example.com",
            "Connection: Close",
            "",
          ].join("\r\n"):Source).pipeTo(cnx.sink)
            .handle(function(o) asserts.assert(o == AllWritten));
        
        cnx.source.all().handle(function(res) {
          asserts.assert(res.isSuccess());
          asserts.done();
          cnx.close();
        });        
      case Failure(e):
        asserts.emit(new Assertion(Failure(e.toString()), 'Open connection'));
        asserts.done();
    });
    
    return asserts;
  }
  
}