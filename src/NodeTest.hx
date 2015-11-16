package;

import haxe.Timer;
import haxe.io.*;
import tink.io.*;
import tink.tcp.*;

using tink.CoreApi;

class NodeTest {
  static var total = 1000;
  static var message = {
    //var accumulated = [for (i in 0...10000) 'Is it me you\'re looking for $i?'].join(' ');
    var bytes = Bytes.ofString('world');
    bytes;
  }
  
  static function main() {
    
    #if nodejs
    haxe.Log.trace = function (d:Dynamic, ?p:haxe.PosInfos) {
      js.Node.console.log('${p.fileName}:${p.lineNumber}', Std.string(d));
    }
    #end
    Server.bind(3000).handle(function (o) {
      var s = o.sure();
      var start = Timer.stamp();
      parallel(function () {
        s.close();
        trace(Timer.stamp() - start);
      });
      
      s.connected.handle(function (cnx) {
        ('hello\r\n' : Source).append
        (cnx.source).pipeTo(cnx.sink).handle(function (x) {
          //trace(x);
          //cnx.source.close();
          //cnx.sink.close();
          cnx.close();
          //s.close();
        });
      });
    });
    
  }
  
  static function sequential(close) {
    var last:Source = message;
    
    for (i in 0...total) {
      
      var cnx = Connection.establish( { host: '127.0.0.1', port: 3000 } );
      last.pipeTo(cnx.sink).handle(function (x) {
        //trace(x);
        cnx.sink.close();
        //cnx.close();
      });
      
      last = cnx.source;
    }
    
    var out = new BytesOutput();
    
    last.pipeTo(Sink.ofOutput('memory buffer', out)).handle(function (x) {
      trace(x);
      close();
    });
  }
  
  static function parallel(close) {
    
    function dec() {
      if (--total == 0) 
        close();
    }
    
    for (i in 0...total) {
      var cnx = Connection.establish( { host: '127.0.0.1', port: 3000 } );
      var write = (message : Source);
      write.pipeTo(cnx.sink).handle(function (x) {
        //trace(x);
        cnx.sink.close();
      });
      
      
      var out = new BytesOutput();
      (cnx.source).pipeTo(Sink.ofOutput('memory buffer', out)).handle(function (y) {
        out.getBytes();
        cnx.source.close();
        dec();
      });       
    }
  }
  
}