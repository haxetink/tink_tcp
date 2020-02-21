package tink.tcp;

import haxe.DynamicAccess;
import haxe.io.Bytes;
import tink.io.Worker;

using tink.io.Source;
using tink.io.Sink;
using tink.CoreApi;

#if sys
import sys.net.Socket;
#end

class Connection {
	public var source(get, never):RealSource;
	public var sink(get, never):RealSink;
	public var name(default, null):String;
	public var peer(default, null):Endpoint;

	var _source:RealSource;
	var _sink:RealSink;

	var onClose:Callback<Connection>;

	public function new(source, sink, name, peer, onClose) {
		this._source = source;
		this._sink = sink;
		this.name = name;
		this.peer = peer;
		this.onClose = onClose;
	}

	public function toString()
		return name;

	public function close() {
		//   source.close();
		sink.end();
		if (onClose != null) {
			onClose.invoke(this);
			onClose = null;
		}
	}

	inline function get_source()
		return _source;

	inline function get_sink()
		return _sink;

	#if (sys)
	static public function wrap(to:Endpoint, s:sys.net.Socket, ?reader, ?writer, ?close:Void->Void):Connection {
		#if !java
		s.setBlocking(false);
		#end
		return new Connection(Source.ofInput('Inbound stream from $to', new SocketInput(s), {worker: reader}),
			Sink.ofOutput('Outbound stream to $to', new SocketOutput(s), {worker: writer}), '[Connection to $to]', to, switch close {
				case null: function()(writer:Worker).work(function() {
						s.close();
						return true;
					});
				case v: v;
			});
	}
	#elseif nodejs
	static public function wrap(to:Endpoint, c:js.node.net.Socket):Connection {
		return new Connection(Source.ofNodeStream('Inbound stream from $to', c), Sink.ofNodeStream('Outbound stream to $to', c), '[Connection to $to]', to,
		function() {});
	}
	#end

	static public function tryEstablish(to:Endpoint, ?reader:Worker, ?writer:Worker):Promise<Connection> {
		var name = '[Connection to $to]';
		function fail(e:Dynamic)
			return Failure(Error.reporter(500, 'Failed to establish $name')(e));
		#if (sys)
		reader = reader.ensure();
		writer = writer.ensure();
		return reader.work(function() return try {
			var s = if (to.secure)
				#if java
				cast new java.net.SslSocket()
				#elseif (haxe_ver > 3.210)
				cast new sys.ssl.Socket()
				#else
				throw 'Secure socket not available'
				#end
			else
				new Socket();

			s.connect(new sys.net.Host(to.host), to.port);
			Success(wrap(to, s, reader, writer));
		} catch (e:Dynamic) fail(e));
		#elseif nodejs
		return Future.async(function(cb) {
			var c:js.node.net.Socket = null;

			function handleConnectError(e)
				cb(fail(e));

			function done() {
				c.removeListener('error', handleConnectError);
				cb(Success(wrap(to, c)));
			}

			c = if (to.secure)
				js.node.Tls.connect(to.port, to.host, done)
			else
				js.node.Net.createConnection(to.port, to.host, done);

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
		return new Connection(cnx.next(function(c):RealSource return c.source), cnx.next(function(c):RealSink return c.sink), name, to, function() {
			cnx.handle(function(o) switch o {
				case Success(cnx):
					cnx.close();
				default:
			});
		});
	}
}

#if sys
private class SocketInput extends haxe.io.Input {
	var sockets:Array<Socket>;
	var counter = 0;

	public function new(s)
		this.sockets = [s];

	function select() {
		#if concurrent
		var selectTime = counter / 10000;
		#else
		var selectTime = counter / 50000;
		#end

		return if (counter <= 10)
			sockets;
		else
			#if java
			{
				Sys.sleep(selectTime);
				sockets;
			}
      #elseif (concurrent && tink_runloop)
      tink.RunLoop.current.synchronously(function() {
        return Socket.select(sockets, [], [], selectTime).read;
      });
      #else
			Socket.select(sockets, [], [], selectTime).read;
			#end
	}

	override public function readBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int {
		if (counter < 100)
			counter++;
		var ret = switch select() {
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
		#if concurrent
		var selectTime = counter / 10000;
		#else
		var selectTime = counter / 50000;
		#end
		return if (counter <= 10)
			sockets;
		else
			#if java
			{
				Sys.sleep(selectTime);
				sockets;
			}
      #elseif (concurrent && tink_runloop)
      tink.RunLoop.current.synchronously(function(){
        return Socket.select([], sockets, [], selectTime).write;
      });
      #else
      Socket.select([], sockets, [], selectTime).write;
			#end
	}

	override public function writeBytes(buffer:haxe.io.Bytes, pos:Int, len:Int):Int {
		if (counter < 100)
			counter++;

		var ret = switch select() {
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
