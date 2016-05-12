package;

import haxe.io.*;
import tink.io.*;
import tink.io.StreamParser;
import tink.tcp.*;
import buddy.*;

using buddy.Should;
using StringTools;
using tink.CoreApi;

class TestIssue3 extends BuddySuite {
	
	public function new() {
		describe("Issue #3", {
			it("Read from a web server", function(done) {
				trace('trying to connect');
				Connection.tryEstablish({host:'www.google.com', port:80}, Worker.get(), Worker.get()).handle(function(o) switch o {
					case Success(cnx):
						trace('connected');
						cnx.source.parse(new Parser()).handle(function(o) switch o {
							case Success(d): 
								trace(d.data);
								done();
							case Failure(f): 
								fail(f);
						});

						("GET /\r\n":Source).pipeTo(cnx.sink).handle(function(o) switch o {
							case SinkFailed(e) | SourceFailed(e):
								fail(e);
							case SinkEnded:
								trace(new Error('sink ended'));
							case AllWritten:
								trace('all written');
						});
					case Failure(f):
						fail(f);
				});
				haxe.Timer.delay(function(){}, 2000);
			});
		});
	}
}

class Parser extends ByteWiseParser<String> {
	var out:BytesOutput;
	public function new() {
		out = new BytesOutput();
		super();
	}
	override function read(c:Int) {
		if(c == -1) return Done(out.getBytes().toString());
		out.writeByte(c);
		return Progressed;
	}
}