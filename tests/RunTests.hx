package;

import buddy.*;

//class RunTests implements Buddy<[
	//TestIssue3,
//]> {}

//TODO: figure out a way to make the above work

import buddy.reporting.ConsoleReporter;

class RunTests {
    public static function main() {
        var reporter = new ConsoleReporter();

        var runner = new buddy.SuitesRunner([
            new TestIssue3(),
        ], reporter);

        runner.run().then(function (_) {
          Sys.exit(if (runner.failed()) 500 else 0);
        });
    }
}