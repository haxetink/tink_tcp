package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
  public static function main() {
    Runner.run(TestBatch.make([
      new EchoTest(),
      new TestConnect(),
      new TestAbort(),
      new TestSinkEndFolding(),
      new TestSessionClosed(),
      #if (nodejs || java || hl || cpp || (eval && eval_tls))
      new TlsTest(),
      new TestServerErrors(),
      #end
    ])).handle(Runner.exit);
  }
}
