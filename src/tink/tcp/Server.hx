package tink.tcp;

#if sys
import sys.net.Host;
import sys.net.Socket;
#end
import tink.io.*;
#if tink_runloop
import tink.runloop.Worker;
import tink.runloop.Task;
#end

using tink.CoreApi;

@:forward
abstract Server(ServerObject) from ServerObject {
  static public function bind(port:Int):Promise<Server> {
    #if java
      return tink.tcp.servers.JavaServer.bind(port);
    #elseif nodejs
      return tink.tcp.servers.NodeServer.bind(port);
    #elseif eval
      return tink.tcp.servers.EvalServer.bind(port);
    // #elseif ((neko || java || cpp) && tink_runloop)
      // return SysServer.bind(port);
    #else
      return Future.sync(Failure(new Error('Not implemented on current platform')));//technically, this is unreachable
    #end
  }
}

interface ServerObject {
  final connected:Signal<Connection>;
  var port(get, never):Int;
  function close():Promise<Noise>;
}

// #if (tink_runloop && (neko || java || cpp))
// class RunloopServer implements ServerObject {
//   final usher:Worker;
//   final releaseKeepAlive:Task;
//   final getScribe:Void->Worker;
//   var boundPort: {
//     function close():Void;
//     function accept(reader:Worker, writer:Worker):Connection;
//   };
//   final connected:Signal<Connection>;
//   final trigger:SignalTrigger<Connection>;
  
//   public function new(usher, getScribe, bind) {
//     this.trigger = Signal.trigger();
//     this.connected = trigger.asSignal();
//     this.usher = usher;
//     this.getScribe = getScribe;
    
//     this.boundPort = bind({ 
//       blocking: 
//           #if concurrent
//             usher.owner != usher
//           #else
//             false
//           #end
//     });
    
//     this.releaseKeepAlive = usher.owner.retain();
    
//     usher.work(accept);    
//   }
  
//   function accept() {
    
//     if (releaseKeepAlive.state != Pending) return;
//     try {
      
//       final scribe = getScribe();
//       final client = boundPort.accept(scribe, scribe);//TODO: consider having separate threads for output to reduce back pressure
      
//       usher.owner.work(() -> trigger.trigger(client));
//     }
//     catch (e:Dynamic) {
//       //do something about this?
//     }
        
//     usher.work(accept);
//   }
  
//   public function close() 
//     if (boundPort != null) {
//       releaseKeepAlive.perform();
//       trigger.clear();
//       boundPort.close();
//       boundPort = null;      
//     }  
// }

// class SysServer extends RunloopServer {
//   public function new(usher, getScribe, port:Int) 
//     super(usher, getScribe, options -> {
//       #if java
//       final s = java.nio.channels.ServerSocketChannel.open();
//       s.bind(new java.net.InetSocketAddress(port));
//       s.configureBlocking(options.blocking);
//       return {
//         close: s.close,
//         accept: (read, write) -> {
//           final client = s.accept();
//           client.configureBlocking(false);
//           final peer = client.getRemoteAddress();
//           final endpoint:Endpoint = 1234;
//           return new Connection(
//             new tink.io.java.JavaSource(client, 'Inbound stream from $endpoint', read),
//             new tink.io.java.JavaSink(client, 'Outbound stream to $endpoint', write),
//             'Connection to $endpoint',
//             endpoint,
//             client.close
//           );
//         }
//       }
//       #else
//       final s = new Socket();
//       s.bind(new Host('0.0.0.0'), port);//TODO: find out how to bind for any address
//       s.listen(0x4000);
//       s.setBlocking(options.blocking);
//       return {
//         close: s.close,
//         accept: (read, write) -> {
//           final client = s.accept();
//           final peer = client.peer();
          
//           return Connection.wrap( { port: peer.port, host: peer.host.toString() }, client, read, write);  
//         }
//       }
//       #end
//     });
  
//   static public function bind(port:Int) {
//     final workers = [for (i in 0...10) tink.RunLoop.current.createSlave()];
//     return Future.sync(
//       Success(
//         (new SysServer(
//           workers.pop(), 
//           () -> workers[Std.random(workers.length)],//the naive hope is that randomness makes it harder to glue down a single worker
//           port
//         ) : Server)
//       )
//     );    
//   }
  
// }

// #end