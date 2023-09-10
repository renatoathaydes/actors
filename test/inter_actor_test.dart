import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

class ActorHasActor with Handler<int, void> {
  final void Function(int) otherActor;

  ActorHasActor(this.otherActor);

  @override
  FutureOr<void> handle(int message) {
    otherActor(message + 1);
  }
}

class MainActor with Handler<int, int> {
  int _sum = 0;

  @override
  FutureOr<int> handle(int message) {
    _sum += message;
    return _sum;
  }
}

void main() {
  group('Actor can receive handle to another Actor and use it to send messages',
      () {
    late Actor<int, int> mainActor;
    late Actor<int, void> otherActor;

    setUp(() {
      mainActor = Actor(MainActor());
      otherActor = Actor(ActorHasActor(mainActor.sender));
    });

    tearDown(() {});

    test('can send msg to actor that sends msg to another actor', () async {
      await otherActor.send(2);
      await otherActor.send(4);
      // there's no way to wait for the actor-to-actor msg to arrive.
      waitUntilEquals(
          () async => await mainActor.send(0), 8, Duration(milliseconds: 500));
    });
  });
}

Future<void> waitUntilEquals<T>(
    Future<T> Function() condition, T expected, Duration timeout) async {
  final limit = DateTime.now().add(timeout);
  T current;
  while ((current = await condition()) != expected) {
    await Future.delayed(Duration(milliseconds: 50));
    if (DateTime.now().isAfter(limit)) {
      throw Exception('not equal to $expected: $current (timeout)');
    }
  }
}
