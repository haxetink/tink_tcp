package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
    public static function main() {
        Runner.run(TestBatch.make([
            new TestIssue3(),
            new TestSecureConnection(),
        ])).handle(Runner.exit);
    }
}