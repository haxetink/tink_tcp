package tink.tcp;

import tink.CoreApi;

enum SessionOutcome {
  GoneGraceful;
  Aborted;
  Failed(e:Error);
}
