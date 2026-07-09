package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
  public static function main() {
    Runner.run(TestBatch.make([
      new EchoTest(),
      new TestConnect(),
      #if (nodejs || java)
      new TlsTest(),
      #end
    ])).handle(Runner.exit);
  }
}
