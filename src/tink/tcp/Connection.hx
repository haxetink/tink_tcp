package tink.tcp;

import tink.io.*;

using tink.CoreApi;

#if sys
  import sys.net.Socket;
#end

class Connection {
	public var source(default, null):Source;
	public var sink(default, null):Sink;
	public var name(default, null):String;
	
	var onClose:Callback<Connection>;
  
	public function new(source, sink, name, onClose) {
		this.source = source;
		this.sink = sink;
		this.name = name;
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
  
  static public function tryEstablish(to:Endpoint, ?reader:Worker, ?writer:Worker) {
    var name = '[Connection to $to]';
    #if (neko || cpp || java)
      var s = new Socket();
      return Future.sync(
        try {
          s.connect(new sys.net.Host(to.host), to.port);
          s.setBlocking(false);
          
          Success(new Connection(
            Source.ofInput('Inbound stream from $to', new SocketInput(s, .001), reader),
            Sink.ofOutput('Outbound stream to $to', new SocketOutput(s, .001), writer),
            name,
            s.close
          ));
        }
        catch (e:Dynamic) 
          Failure(Error.reporter(500, 'Failed to establish $name')(e))
      );
    #elseif nodejs
      
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
  var selectTime:Float = 0;
	
	public function new(s, selectTime) {
		this.sockets = [s];
    this.selectTime = selectTime;
  }
	
  function select()
    return  
      if (selectTime > 0)
        Socket.select(sockets, null, null, .0).read;
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
  var selectTime:Float = 0;
  
	public function new(s, selectTime) {
		this.sockets = [s];
    this.selectTime = selectTime;
  }
    
  function select()
    return  
      if (selectTime > 0)
        Socket.select(null, sockets, null, .0).write;
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