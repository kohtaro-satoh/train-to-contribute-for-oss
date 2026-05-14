- The "local → remote only" rule applies **per relation**, not per controller;
  two controllers may simultaneously hold two independent relations
  (A→B for B's resources, B→A for A's resources), enabling mutual sharing
  without any bidirectional channel.