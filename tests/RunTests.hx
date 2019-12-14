package;

import tink.testrunner.*;
import tink.unit.*;

class RunTests {
    public static function main() {
        Runner.run(TestBatch.make([
            new TestConnect(),
            #if nodejs
            new TestAccept(),
            #end
        ])).handle(Runner.exit);
        
        
        #if java
        // HACK: prevent early exit in java, to be investigated
        haxe.Timer.delay(function() trace('delay'), 50000);
        #end
    }
}