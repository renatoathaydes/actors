import 'dart:async';
import 'dart:core';
import 'dart:io';

import 'package:actors/actors.dart';

/// Example Handler that can be made an Actor.
class Counter with Handler<int, int> {
  int _count = 0;

  @override
  int handle(int n) => _count += n;
}

/// Expected printed output from the main function.
Iterator<String> _expectedLines = [
  '1', '2', '8', '16', '10', '12', '14', '16', '2', '3', '8', '10', '0', '1' //
].iterator;

// This function overrides Dart's "print" so we can verify the printed output
void printAndCheck(Zone self, ZoneDelegate parent, Zone zone, String line) {
  _expectedLines.moveNext();
  if (line == _expectedLines.current) {
    stdout.writeln(line);
  } else {
    throw Exception('Unexpected line: $line, not ${_expectedLines.current}');
  }
}

void main() async {
  await runZoned(() async {
    await actorExample();
    await actorGroupExample();
    await localMessengerExample();
    await streamActorExample();
  }, zoneSpecification: ZoneSpecification(print: printAndCheck));
}

Future actorExample() async {
  // Create an Actor from a Handler
  final actor = Actor(Counter());
  print(await actor.send(1)); // 1
  print(await actor.send(1)); // 2
  print(await actor.send(6)); // 8
  print(await actor.send(8)); // 16

  // Close the actor to stop its Isolate
  await actor.close();
}

int times2(int n) => n * 2;

Future actorGroupExample() async {
  // create a group of 4 actors from a simple top-level function...
  // in this example, any of the actors in the group could handle a
  // particular message.
  // Notice that lambdas cannot be provided to "of", only top-level functions.
  final group = ActorGroup.of(times2, size: 4);
  print(await group.send(5)); // 10
  print(await group.send(6)); // 12
  print(await group.send(7)); // 14
  print(await group.send(8)); // 16

  await group.close();
}

// A Handler that returns a Stream must use a StreamActor, not an Actor.
class StreamGenerator with Handler<int, Stream<int>> {
  @override
  Stream<int> handle(int message) {
    return Stream.fromIterable(Iterable.generate(message, (i) => i));
  }
}

Future streamActorExample() async {
  // Create an StreamActor from a Handler that returns Stream.
  final actor = StreamActor(StreamGenerator());
  final stream = actor.send(2);
  await for (final item in stream) {
    print(item); // 0, 1
  }
  await actor.close();
}

Future localMessengerExample() async {
  Messenger<int, int> messenger;

  // a Messenger can be local
  messenger = LocalMessenger(Counter());
  print(await messenger.send(2)); // 2
  await messenger.close();

  // or it can be an Actor
  messenger = Actor(Counter());
  print(await messenger.send(3)); // 3
  await messenger.close();

  // or an ActorGroup
  messenger = ActorGroup.of(times2, size: 2);
  print(await messenger.send(4)); // 8
  print(await messenger.send(5)); // 10
  await messenger.close();
}
