package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
  public static function main() {
    Runner.run(TestBatch.make([
      new EchoTest(),
      new TestConnect(),
      #if nodejs
      new NodeTlsTest(),
      #end
      #if java
      new JavaTlsTest(),
      #end
    ])).handle(Runner.exit);
  }
}
