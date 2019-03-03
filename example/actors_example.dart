import 'dart:io' show exit;
import 'dart:isolate' show Isolate;

import 'package:actors/actors.dart';

class Two with Handler<int, int> {
  int handle(int n) => n * 2;
}

main() async {
  await actorExample();
  await actorGroupExample();

  exit(0);
}

Future actorExample() async {
  final actor = Actor(Two());
  print(await actor.send(5)); // 10
  print(await actor.send(6)); // 12
  print(await actor.send(7)); // 14
  print(await actor.send(8)); // 16

  final isolate = await actor.isolate;
  isolate.kill(priority: Isolate.immediate);
}

Future actorGroupExample() async {
  // create a group of 4 actors
  final group = ActorGroup(Two(), size: 4);
  print(await group.send(5)); // 10
  print(await group.send(6)); // 12
  print(await group.send(7)); // 14
  print(await group.send(8)); // 16

  for (var actor in group.actors) {
    (await actor.isolate).kill(priority: Isolate.immediate);
  }
}
