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
    static public function wrap(to:Endpoint, s:sys.net.Socket, ?reader, ?writer, ?close:Void->Void):Connection {
      s.setBlocking(false);
      return
        new Connection(
          Source.ofInput('Inbound stream from $to', new SocketInput(s), reader),
          Sink.ofOutput('Outbound stream to $to', new SocketOutput(s), writer),
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
        Source.ofNodeStream('Inbound stream from $to', c),
        Sink.ofNodeStream('Outbound stream to $to', c),
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
      reader = reader.ensure();
      writer = writer.ensure();
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
  var counter = 0;
  
  public function new(s)
    this.sockets = [s];
    
  function select() {
    var selectTime = counter / 10000;
    
    return  
      if (counter <= 10)
        sockets;
      else
        #if java 
        {
          Sys.sleep(selectTime);
          sockets;
        }
        #else
          Socket.select(sockets, [], [], selectTime).read;
        #end
  }
    
  override public function readBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int {
    if (counter < 100)
      counter++;
    var ret = 
      switch select() {
        case [s]: s.input.readBytes(buffer, pos, len);
        default: 0;
      }
      
    if (ret != 0)
      counter = 0;
          
    return ret;      
  }
  
  override public function close():Void {
    super.close();
    sockets[0].shutdown(true, false);
  }
      
}

private class SocketOutput extends haxe.io.Output {
  var sockets:Array<Socket>;
  var counter = 0;
  
  public function new(s)
    this.sockets = [s];
    
  function select() {
    var selectTime = counter / 10000;
    return  
      if (counter <= 10)
        sockets;
      else
        #if java 
        {
          Sys.sleep(selectTime);
          sockets;
        }
        #else
          Socket.select([], sockets, [], selectTime).write;
        #end
  }
  
  override public function writeBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int {
    if (counter < 100)
      counter++;
    
    var ret =
      switch select() {
        case [s]: s.output.writeBytes(buffer, pos, len);
        default: 0;
      }
      
    if (ret != 0)
      counter = 0;
        
    return ret;
  }
      
  override public function close():Void {
    super.close();
    sockets[0].shutdown(false, true);
  }
  
}
#end
