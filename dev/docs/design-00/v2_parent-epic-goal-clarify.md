- The "local → remote only" rule applies **per relation**, not per controller;
  controllers may simultaneously hold multiple independent relations
  (e.g. A→B for B's resources, B→A for A's resources, A→C for C's resources),
  enabling mutual sharing without any bidirectional channel.