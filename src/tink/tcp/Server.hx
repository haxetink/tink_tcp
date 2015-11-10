package tink.tcp;

#if sys
import sys.net.Host;
import sys.net.Socket;
import tink.runloop.Worker;
import tink.runloop.Task;
#end

using tink.CoreApi;

@:forward
abstract Server(ServerObject) from ServerObject {
  @:require(neko || java || cpp || nodejs)
  static public function bind(port:Int):Surprise<Server, Error> {
    #if (neko || java || cpp)
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
    #elseif nodejs
    
    #else
      return null;
    #end
  }
}

interface ServerObject {
  var connected(get, never):Signal<Connection>;
  function close():Void;
}


#if (neko || java || cpp)
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
		this.socket.bind(new Host('localhost'), port);
		this.socket.listen(0x4000);
				
		//if (usher == usher.owner) 
			
		//if (usher.step() != WrongThread)
    this.socket.setBlocking(false);
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
			
			var client = socket.accept(),
					scribe = getScribe();
			
			#if !java
			client.setBlocking(false);
			#end
      var peer = client.peer();
			//TODO: consider having separate threads for output to reduce back pressure
			var connection = Connection.wrap( { port: peer.port, host: peer.host.toString() }, client, scribe, scribe);			
      usher.owner.work(function () _connected.trigger(connection));
		}
		catch (e:Dynamic) {
      if (releaseKeepAlive.state == Pending)
        if (e != 'Blocking' && e != haxe.io.Error.Blocked) 
          throw e;
		}
				
		usher.work(accept);
	}
	
	public function close() {
		releaseKeepAlive.perform();
		
		_connected.clear();
		socket.close();
	}
  
}
#end