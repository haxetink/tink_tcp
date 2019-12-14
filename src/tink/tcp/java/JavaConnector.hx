package tink.tcp.java;

import java.lang.Integer;
import java.lang.Throwable;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import java.net.SocketAddress;
import java.net.InetSocketAddress;
import tink.io.Sink;

using tink.io.Source;
using tink.CoreApi;

class JavaConnector {
	static public function connect(to:Endpoint, handler:Handler):Promise<Noise> {
		return new Promise(function(resolve, reject) {
			var socket = AsynchronousSocketChannel.open();
			var remote:SocketAddress = new InetSocketAddress(to.host, to.port);
			socket.connect(remote, 0, new ConnectHandler(resolve, reject, socket, handler));
		});
	}
}

private class ConnectHandler implements CompletionHandler<java.lang.Void, Int>  {
	var resolve:Callback<Noise>;
	var reject:Callback<Error>;
	var socket:AsynchronousSocketChannel;
	var handler:Handler;
	
	public function new(resolve, reject, socket, handler) {
		this.resolve = resolve;
		this.reject = reject;
		this.socket = socket;
		this.handler = handler;
	}
	
	public function completed(result:java.lang.Void, attachment:Int) {
		var remote:InetSocketAddress = cast socket.getRemoteAddress();
		var local:InetSocketAddress = cast socket.getLocalAddress();
		var source = Source.ofJavaSocketChannel('Incoming stream of connection to ${remote.toString()}', socket);
		var sink = Sink.ofJavaSocketChannel('Outgoing stream of connection to ${remote.toString()}', socket);
		var remote = new Endpoint(remote.getHostName(), remote.getPort());
		var local = new Endpoint(local.getHostName(), local.getPort());
		var sourceClosed = Future.trigger();
		
		handler.handle({from: remote, to: local, stream: source, closed: sourceClosed}).handle(function (outgoing) {
			outgoing.stream.pipeTo(sink, {end: true}).handle(function (o) {
				// TODO: support allowHalfOpen
				switch o {
					case SinkFailed(e, _): reject.invoke(e);
					case SinkEnded(_, { depleted: false }): reject.invoke(new Error('$sink closed before all data could be written'));
					default: resolve.invoke(Noise);
				}
			});
		});
	}
	
	public function failed(exc:Throwable, attachment:Int) {
		reject.invoke(Error.withData('Connection to ${socket.getRemoteAddress()} failed, reason: ' + exc.getMessage(), exc));
	}
}