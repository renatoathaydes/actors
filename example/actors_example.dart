import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';

/// Example actor that keeps a counter as its state.
///
/// All it takes for a Dart class to become an Actor is for it to
/// mixin [Handler] and be instantiated like:
///
/// ```dart
/// final actor = Actor(Counter());
/// ```
class Counter with Handler<int, int> {
  int _count = 0;

  @override
  int handle(int n) => _count += n;
}

/// Expected printed output from the main function.
Iterator<String> _expectedLines = [
  // Actors example
  '1', '2', '8', '16', //
  // ActorGroup example
  '10', '12', '14', '16', '18', '20', //
  // StreamActor example
  '0', '1', //
  // LocalMessenger example
  '2', '3', '8', '10', //
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
    await streamActorExample();
    await localMessengerExample();
  }, zoneSpecification: ZoneSpecification(print: printAndCheck));
}

Future actorExample() async {
  stdout.writeln('Actor example');

  // Create an Actor from a Handler
  final actor = Actor(Counter());
  print(await actor.send(1)); // 1
  print(await actor.send(1)); // 2
  print(await actor.send(6)); // 8
  print(await actor.send(8)); // 16

  // Close the actor to stop its Isolate
  await actor.close();
}

int times2(int n) {
  // print the name of the current Isolate for debugging purposes
  stdout.write('${Isolate.current.debugName.padRight(8)} - times2($n)\n');
  return n * 2;
}

Future actorGroupExample() async {
  stdout.writeln('ActorGroup example');

  // create a group of 4 actors from a simple top-level function...
  // in this example, any of the actors in the group could handle a
  // particular message (default behaviour is to use round-robin),
  // and as we don't wait before sending the next message,
  // messages are handled concurrently!
  final group = ActorGroup.of(times2, size: 4);

  // send a bunch of messages and remember the Futures with answers
  final answers =
      Iterable.generate(6, (index) => index + 5).map(group.send).toList();

  // print each response (type shown explicitly for clarity)
  for (FutureOr<int> answer in answers) {
    print(await answer); // prints 10, then 12, 14, 16, 18, 20
  }

  // closing the group will cause any pending message deliveries to fail!
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
  stdout.writeln('StreamActor example');

  // Create an StreamActor from a Handler that returns Stream.
  final actor = StreamActor(StreamGenerator());
  final stream = actor.send(2);
  await for (final item in stream) {
    print(item); // 0, 1
  }
  await actor.close();
}

Future localMessengerExample() async {
  stdout.writeln('LocalMessenger example');

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
