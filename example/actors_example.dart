import 'dart:io' show exit;
import 'dart:isolate' show Isolate;

import 'package:actors/actors.dart';

class Counter with Handler<int, int> {
  int _count = 0;

  int handle(int n) => _count += n;
}

main() async {
  await actorExample();
  await actorGroupExample();
  await localMessengerExample();

  exit(0);
}

Future actorExample() async {
  final actor = Actor(Counter());
  print(await actor.send(1)); // 1
  print(await actor.send(1)); // 2
  print(await actor.send(6)); // 8
  print(await actor.send(8)); // 16

  final isolate = await actor.isolate;
  isolate.kill(priority: Isolate.immediate);
}

int times2(n) => n * 2;

Future actorGroupExample() async {
  // create a group of 4 actors...
  // in this example, any of the actors in the group could handle a
  // particular message.
  // Notice that lambdas cannot be provided to "of", only real functions.
  final group = ActorGroup.of(times2, size: 4);
  print(await group.send(5)); // 10
  print(await group.send(6)); // 12
  print(await group.send(7)); // 14
  print(await group.send(8)); // 16

  for (var actor in group.actors) {
    (await actor.isolate).kill(priority: Isolate.immediate);
  }
}

Future localMessengerExample() async {
  Messenger<int, int> messenger;

  // a Messenger can be local
  messenger = LocalMessenger(Counter());
  print(await messenger.send(2)); // 2

  // or it can be an Actor
  messenger = Actor(Counter());
  print(await messenger.send(3)); // 3

  // or an ActorGroup
  messenger = ActorGroup.of(times2, size: 2);
  print(await messenger.send(4)); // 8
  print(await messenger.send(5)); // 10
}
