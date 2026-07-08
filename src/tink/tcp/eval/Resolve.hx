#if eval
package tink.tcp.eval;

import eval.luv.*;
import eval.luv.SockAddr.SocketType;

using tink.CoreApi;

class Resolve {
	static final ipv4 = ~/^(\d+\.\d+\.\d+\.\d+)$/;

	public static function resolveEndpoint(host:String, port:Int, ?loop:Loop):Promise<SockAddr> {
		if (ipv4.match(host)) {
			return switch SockAddr.ipv4(host, port) {
				case Ok(addr): Future.sync(Success(addr));
				case Error(e): Future.sync(Failure(luvError(e, 'Failed to parse address $host:$port')));
			};
		}

		final l = loop ?? EvalLoop.defaultLoop();
		return new Promise((resolve, reject) -> {
			Dns.getAddrInfo(l, host, Std.string(port), null, function(result) {
				switch result {
					case Error(e):
						reject(luvError(e, 'Failed to resolve $host:$port'));
					case Ok(addrs):
						final match = addrs.filter(info -> info.sockType == STREAM);
						if (match.length == 0)
							reject(new Error('No TCP address found for $host:$port'));
						else
							resolve(match[0].addr);
				}
			});
			return null;
		});
	}

	static function luvError(e:UVError, message:String):Error {
		return Error.withData('$message: ${e.toString()}', e);
	}
}
#end
