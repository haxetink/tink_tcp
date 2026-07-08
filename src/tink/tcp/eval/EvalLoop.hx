#if eval
package tink.tcp.eval;

import eval.luv.Loop;

using tink.CoreApi;

class EvalLoop {
	public static function defaultLoop():Loop {
		return sys.thread.Thread.current().events;
	}

	public static function runWithPump<T>(work:Void->Future<T>, ?loop:Loop):Future<T> {
		final l = loop ?? defaultLoop();
		final f = work().eager();
		while (true) {
			switch f.status {
				case Ready(_): break;
				default:
					if (!l.run(NOWAIT))
						l.run(ONCE);
			}
		}
		return f;
	}
}
#end
