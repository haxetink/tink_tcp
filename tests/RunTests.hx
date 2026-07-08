package;

import tink.testrunner.*;
import tink.unit.*;
#if java
import tink.io.java.OnMainThread;
#end

class RunTests {
    public static function main() {
        #if java
        OnMainThread.init();
        #end
        #if eval
        tink.tcp.eval.EvalLoop.runWithPump(() -> Runner.run(TestBatch.make([
            new EchoTest(),
            new TestConnect(),
        ]))).handle(Runner.exit);
        #else
        Runner.run(TestBatch.make([
            new EchoTest(),
            new TestConnect(),
        ])).handle(Runner.exit);
        #end
    }
}
