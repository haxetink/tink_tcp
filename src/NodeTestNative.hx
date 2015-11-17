package;

import haxe.Timer;
import js.Node;
import js.node.Buffer;
import js.node.Fs;
import js.node.Net;
import js.node.net.Socket;
import js.node.stream.Writable;

class NodeTestNative {
  static var total = 100;
  static var message = {
    var s = [for (i in 0...10000) 'Is it me you\'re looking for $i?'].join(' ');
    var buf = new Buffer(s, 'utf8');    
    buf;
  }
  static function main() {
    
    #if nodejs
    haxe.Log.trace = function (d:Dynamic, ?p:haxe.PosInfos) {
      js.Node.console.log('${p.fileName}:${p.lineNumber}', Std.string(d));
    }
    #end
    
    var start = Timer.stamp();
    var out = Fs.createWriteStream('out.txt');
    var server = Net.createServer(function (socket) {
      socket.write('\nhello\n');
      socket.pipe(socket);
    });
    server.listen(3000);
    
    parallel(out, function () {
      server.close();
      out.end();
      trace(Timer.stamp() - start);
    });
  }
  
  static function sequential(out:IWritable, close) {
    var last:Socket = null;
    for (i in 0...total) {
      var socket = Net.createConnection(3000, '127.0.0.1');
      
      if (last == null)
        socket.end(message);
      else
        last.pipe(socket);
        
      last = socket;
    }
    
    last.pipe(out).on('unpipe', close );
  }
  
  static function parallel(out, close) {
    
    function dec() 
      if (--total == 0) 
        close();
    
    for (i in 0...total) {
      var socket = Net.createConnection(3000, '127.0.0.1');
      socket.end(message);
      socket.on('close', function () {
        dec();
      });
      socket.pipe(out, { end: false } );
    }
    
  }
  
}