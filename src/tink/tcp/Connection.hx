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
		if (onClose != null) {
			onClose.invoke(this);
			onClose = null;
		}
		source.close();
		sink.close();
	}
  
  static public function establish(to:Endpoint, ?reader:Worker, ?writer:Worker) {
    var name = '[Connection to $to]';
    #if (neko || cpp || java)
      var s = new Socket();
      return Future.sync(
        try {
          s.connect(new sys.net.Host(to.host), to.port);
          s.setBlocking(false);
          Success(new Connection(
            //Source.ofInput('Inbound stream from $to', new SocketInput(s), worker),
            Source.ofInput('Inbound stream from $to', s.input, reader),
            Sink.ofOutput('Outbound stream to $to', s.output, writer),
            //Sink.ofOutput('Outbound stream to $to', new SocketOutput(s), worker),
            name,
            s.close
          ));
        }
        catch (e:Dynamic) 
          Failure(Error.reporter(500, 'Failed to establish $name')(e))
      );
    #else
      #error
    #end
  }
}

#if sys
private class SocketInput extends haxe.io.Input {
	var sockets:Array<Socket>;
	
	public function new(s)
		this.sockets = [s];
	
	override public function readBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int 
		return 
			switch Socket.select(sockets, null, null, .0).read {
				case [s]: s.input.readBytes(buffer, pos, len);
				default: 0;
			}
	
}


private class SocketOutput extends haxe.io.Output {
	var sockets:Array<Socket>;
	public function new(s) 
		this.sockets = [s];
	
	override public function writeBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int 
		return 
			switch Socket.select(null, sockets, null, .0).write {
				case [s]: s.output.writeBytes(buffer, pos, len);
				default: 0;
			}
	
}
#end