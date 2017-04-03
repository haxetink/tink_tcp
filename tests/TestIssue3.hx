package;

import haxe.io.*;
import tink.io.*;
import tink.io.Pipe;
import tink.tcp.*;
import tink.unit.*;
import tink.testrunner.*;
using StringTools;
using tink.CoreApi;

@:name("Issue #3")
class TestIssue3{
  
  public function new() {}
  
  @:describe("Read from a web server")
  public function test(asserts:AssertionBuffer) {
    
    Connection.tryEstablish({host:'www.example.com', port:80}).handle(function(o) switch o {
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

