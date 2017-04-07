package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
    public static function main() {
        Runner.run(TestBatch.make([
            new TestIssue3(),
            // #if (haxe_ver > 3.210) new TestSecureConnection(), #end
        ])).handle(Runner.exit);
    }
}