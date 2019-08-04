import 'dart:async';
import 'dart:core';
import 'dart:io' ;
import 'dart:isolate' show Isolate;

import 'package:actors/actors.dart';

class Counter with Handler<int, int> {
  int _count = 0;

  int handle(int n) => _count += n;
}

Iterator<String> _expectedLines = [
  '1', '2', '8', '16', '10', '12', '14', '16', '2', '3', '8', '10' //
].iterator;

// This function overrides Dart's "print" so we can verify the printed output
void printAndCheck(Zone self, ZoneDelegate parent, Zone zone, String line) {
  _expectedLines.moveNext();
  if (line == _expectedLines.current) {
    stdout.writeln(line);
  } else {
    throw Exception("Unexpected line: $line, not ${_expectedLines.current}");
  }
}

void main() async {
  await runZoned(() async {
    await actorExample();
    await actorGroupExample();
    await localMessengerExample();
  }, zoneSpecification: ZoneSpecification(print: printAndCheck));
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

int times2(int n) => n * 2;

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

  await group.close();
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

  await messenger.close();
}
