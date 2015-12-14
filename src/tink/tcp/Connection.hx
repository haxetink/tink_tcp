package tink.tcp;

import haxe.DynamicAccess;
import haxe.io.Bytes;
import tink.io.*;

using tink.CoreApi;

#if sys
  import sys.net.Socket;
#end

class Connection {
	public var source(default, null):Source;
	public var sink(default, null):Sink;
	public var name(default, null):String;
	public var peer(default, null):Endpoint;
  
	var onClose:Callback<Connection>;
  
	public function new(source, sink, name, peer, onClose) {
		this.source = source;
		this.sink = sink;
		this.name = name;
    this.peer = peer;
		this.onClose = onClose;
	}
	
	public function toString() 
    return name;
	
	public function close() {
		source.close();
		sink.close();
		if (onClose != null) {
			onClose.invoke(this);
			onClose = null;
		}
	}
  
  #if (neko || cpp || java)
    static public function wrap(to:Endpoint, s:sys.net.Socket, ?selectTime = .001, ?reader, ?writer, ?close:Void->Void):Connection {
      s.setBlocking(false);
      return
        new Connection(
          Source.ofInput('Inbound stream from $to', new SocketInput(s, selectTime), reader),
          Sink.ofOutput('Outbound stream to $to', new SocketOutput(s, selectTime), writer),
          '[Connection to $to]',
          to,
          switch close {
            case null: function () writer.work(function () { s.close(); return true; });
            case v: v;
          }  
        );
    }
  #elseif nodejs
    static public function wrap(to:Endpoint, c:js.node.net.Socket):Connection {
      return new Connection(
        Source.ofNodeStream(c, 'Inbound stream from $to'),
        Sink.ofNodeStream(c, 'Outbound stream to $to'),
        '[Connection to $to]',
        to,
        function () {}
      );
    }
  #end
  
  static public function tryEstablish(to:Endpoint, ?reader:Worker, ?writer:Worker):Surprise<Connection, Error> {
    var name = '[Connection to $to]';
    function fail(e:Dynamic) 
      return Failure(Error.reporter(500, 'Failed to establish $name')(e));
    #if (neko || cpp || java)
      return reader.work(function () return
        try {
          var s = new Socket();
          s.connect(new sys.net.Host(to.host), to.port);
          Success(wrap(to, s, reader, writer));
        }
        catch (e:Dynamic) 
          fail(e)
      );
    #elseif nodejs
      return Future.async(function (cb) {
        
        var c:js.node.net.Socket = null;
        
        function handleConnectError(e) cb(fail(e));
        
        c = js.node.Net.createConnection(to.port, to.host, function () {
          c.removeListener('error', handleConnectError);
          cb(Success(wrap(to, c)));
        });
        
        c.once('error', handleConnectError);
      });
    #elseif flash
    #else
      #error
    #end
  }
  
  static public function establish(to:Endpoint, ?reader, ?writer):Connection {
    var name = '[Connection to $to]',
        cnx = tryEstablish(to, reader, writer);
    return 
      new Connection(
        cnx >> function (c:Connection) return c.source,
        cnx >> function (c:Connection) return c.sink,
        name,
        to,
        function () {
          cnx.handle(function (o) switch o {
            case Success(cnx):
              cnx.close();
            default:
          });
        }
      );
  }
}

#if sys
private class SocketInput extends haxe.io.Input {
	var sockets:Array<Socket>;
  var selectTime:Float;
	
	public function new(s, selectTime) {
		this.sockets = [s];
    this.selectTime = 
      #if java
        -1;
      #else
        selectTime;
      #end
  }
	
  function select()
    return  
      if (selectTime >= 0)
        Socket.select(sockets, null, null, selectTime).read;
      else
        sockets;
    
	override public function readBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int 
		return 
			switch select() {
				case [s]: s.input.readBytes(buffer, pos, len);
				default: 0;
			}
	
  override public function close():Void {
    super.close();
    sockets[0].shutdown(true, false);
  }
      
}

private class SocketOutput extends haxe.io.Output {
	var sockets:Array<Socket>;
  var selectTime:Float;
  
	public function new(s, selectTime) {
		this.sockets = [s];
    this.selectTime = 
      #if java
        -1;
      #else
        selectTime;
      #end
  }
    
  function select()
    return  
      if (selectTime >= 0)
        Socket.select(null, sockets, null, selectTime).write;
      else
        sockets;
	
	override public function writeBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int 
		return 
			switch select() {
				case [s]: s.output.writeBytes(buffer, pos, len);
				default: 0;
			}
      
  override public function close():Void {
    super.close();
    sockets[0].shutdown(false, true);
  }
	
}
#end