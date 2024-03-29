import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';

/// Example actor that counts how many messages it has received.
///
/// All it takes for a Dart class to become an Actor is for it to
/// mixin [Handler] and be instantiated like:
///
/// ```dart
/// final actor = Actor(Accumulator());
/// ```
class Accumulator with Handler<int, int> {
  int _value;

  Accumulator([int initialValue = 0]) : _value = initialValue;

  @override
  int handle(int n) => _value += n;
}

String withIsolateName(message) => '[${Isolate.current.debugName}] $message';

void main() async {
  final actor = await statefulActorExample();
  final actor2 = await functionalActorExample();

  // close the Actors to terminate their Isolates
  for (final a in [actor, actor2]) {
    await a.close();
  }
}

Future<Actor> statefulActorExample() async {
  // create an Actor from a Handler
  final actor = Actor.create(() => Accumulator(6));

  // send messages to the actor
  actor.send(26);

  // await for an answer from the actor
  final answer = await actor.send(10);
  print("StatefulActor's final answer is $answer");

  return actor;
}

Future<Actor> functionalActorExample() async {
  // we can also create non-stateful actors from a function or lambda
  String sayHi(String name) => withIsolateName('Hi $name!');
  print(withIsolateName('Running in the main Isolate'));

  final actor = Actor.of(sayHi);
  print(await actor.send(Platform.environment['USER'] ?? 'anonymous'));

  return actor;
}
