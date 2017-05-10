package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
    public static function main() {
        Runner.run(TestBatch.make([
            new TestConnect(),
            // new TestAccept(),
        ])).handle(Runner.exit);
    }
}