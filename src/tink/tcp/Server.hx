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
  /**
   * Attempts binding a server to a port.
   * 
   * Requires either combination:
   * 
   * - `-lib nodejs` (and `-js` of course)
   * - `-lib tink_runloop` and one of `-neko` or `-java` or `-cpp`
   */
  @:require(neko || java || cpp || nodejs)
  #if (neko || java || cpp)
    @:require(tink_runloop)
  #end
  static public function bind(port:Int):Surprise<Server, Error> {
    #if ((neko || java || cpp) && tink_runloop)
      return SysServer.bind(port);
    #elseif nodejs
      return NodeServer.bind(port);
    #else
      return Future.sync(Failure(new Error('Not implemented on current platform')));//technically, this is unreachable
    #end
  }
}

interface ServerObject {
  var connected(get, never):Signal<Connection>;
  function close():Void;
}


#if (tink_runloop && (neko || java || cpp))
class SysServer implements ServerObject {
	var socket:Socket;
	var usher:Worker;
	
	var releaseKeepAlive:Task;
	var getScribe:Void->Worker;
	
	var _connected:SignalTrigger<Connection>;
	
	public var connected(get, never):Signal<Connection>;
	
	inline function get_connected() 
		return _connected.asSignal();
	
	public function new(usher:Worker, getScribe, port:Int) {
		
		this._connected = Signal.trigger();
		
		this.socket = new Socket();
    //TODO: the two steps below should be done by the usher
		this.socket.bind(new Host('0.0.0.0'), port);
		this.socket.listen(0x4000);
							
		if (#if concurrent usher.step() != WrongThread #else true #end)
      #if java {
        @:privateAccess this.socket.server.setSoTimeout(1);
      }
      #else
        this.socket.setBlocking(false);
      #end
      
		this.usher = usher;
		this.getScribe = getScribe;
		
		this.releaseKeepAlive = usher.owner.retain();
		
		usher.work(accept);
	}
	
	function accept() {
    
		if (releaseKeepAlive.state != Pending) return;
		try {
			//if (usher == usher.owner && currentlyBusy == 0 && Math.random() > .75)
				//Sys.sleep(.001);
        
      //the above is a left over attempt to avoid maxing out a core with busy waiting
        
			var client = socket.accept(),
					scribe = getScribe();
			
      var peer = client.peer();
			//TODO: consider having separate threads for output to reduce back pressure
			var connection = Connection.wrap( { port: peer.port, host: peer.host.toString() }, client, scribe, scribe);			
      usher.owner.work(function () _connected.trigger(connection));
		}
		catch (e:Dynamic) {
      //if (releaseKeepAlive.state == Pending) {
        //if (e != 'Blocking' && e != haxe.io.Error.Blocked) 
          //throw e;
      //}
		}
				
		usher.work(accept);
	}
	
	public function close() {
		releaseKeepAlive.perform();
		
		_connected.clear();
		socket.close();
	}
  
  static public function bind(port:Int) {
    var workers = [for (i in 0...10) tink.RunLoop.current.createSlave()];
    return Future.sync(
      Success(
        (new SysServer(
          workers.pop(), 
          function () {
            return workers[Std.random(workers.length)];//the naive hope is that randomness makes it harder to glue down a single worker
          },
          port
        ) : Server)
      )
    );    
  }
  
}
#elseif nodejs
class NodeServer implements ServerObject {
  var native:js.node.net.Server;
  public var connected(get, null):Signal<Connection>;
  
  function get_connected()
    return connected;
    
  public function new(server) {
    this.native = server;
    var t = Signal.trigger();
    native.on('connection', function (c:js.node.net.Socket) {
      t.trigger(Connection.wrap({ port: c.remotePort, host: c.remoteAddress }, c));
    });
    connected = t;
  }
  
  public function close() {
    native.close();
  }
  
  static public function bind(port:Int) {
    var server = js.node.Net.createServer();
    server.listen(port);
    return 
      Future.async(function (cb) {
        server.on('listening', function (_) {
          cb(Success((new NodeServer(server) : Server)));
        });
        server.on('error', function (e) {
          cb(Failure(new Error('Failed to open server on port $port because $e')));
        });
      });
  }

}
#end