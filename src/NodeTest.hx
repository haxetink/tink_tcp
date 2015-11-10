package;

import haxe.Timer;
import haxe.io.*;
import tink.io.*;
import tink.tcp.*;

using tink.CoreApi;

class NodeTest {

  static function main() {
    
    #if nodejs
    haxe.Log.trace = function (d:Dynamic, ?p:haxe.PosInfos) {
      js.Node.console.log('${p.fileName}:${p.lineNumber}', Std.string(d));
    }
    #end
    
    Server.bind(3000).handle(function (o) {
      var s = o.sure();
      s.connected.handle(function (cnx) {
        ('hello\r\n' : Source).append(cnx.source).pipeTo(cnx.sink).handle(function (x) {
          trace(x);
          cnx.source.close();
          cnx.sink.close();
          s.close();
        });
      });
    });
    
    var write = IdealSource.create();
    var accumulated = [for (i in 0...1200) "Is it me you're looking for $i?"].join(' ');
    var bytes = Bytes.ofString(accumulated);
    
    for (i in 0...10)
      write.write(bytes);
    write.end();
    
    var cnx = Connection.establish( { host: '127.0.0.1', port: 3000 } );
    
    write.pipeTo(cnx.sink).handle(function (x) {
      trace(x);
      cnx.sink.close();
    });
    
    var start = Timer.stamp();
    
    var out = new BytesOutput();
    ('foo':Source).append('bar').append('baz').append(cnx.source).pipeTo(Sink.ofOutput('memory buffer', out)).handle(function (y) {
      trace(y);
      cnx.source.close();
      //waiting = false;
      trace(Timer.stamp() - start);
      //Sys.getChar(true);
      //v.close();
    });       
  }
  
}