package;

import haxe.io.*;
import tink.io.*;
import tink.tcp.*;
import buddy.*;

using buddy.Should;
using StringTools;
using tink.CoreApi;

class TestIssue3 extends BuddySuite {
  
  public function new() {
    describe("Issue #3", {
      it("Read from a web server", function(done) {
        trace('trying to connect');
        Connection.tryEstablish({host:'www.example.com', port:80}).handle(function(o) switch o {
          case Success(cnx):
            trace('connected');

            ([
                "GET /",
                "Host: www.example.com",
                "Connection: Close",
             ].concat([""]).join("\r\n"):Source).pipeTo(cnx.sink).handle(function(o) switch o {
              case SinkFailed(e) | SourceFailed(e):
                fail(e);
              case SinkEnded:
                trace(new Error('sink ended'));
              case AllWritten:
                trace('all written');
            });
            
            cnx.source.all().handle(function(res) {
              switch res {
                case Success(d):
                  trace('received ${d.length} bytes');
                  done();
                case Failure(f): 
                  fail(f);
              }
              cnx.close();
            });            
          case Failure(f):
            fail(f);
        });
      });
    });
  }
  
}

