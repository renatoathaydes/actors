import 'package:actors/actors.dart';
import 'package:test/test.dart';

class IntParserActor with Handler<String, int> {
  @override
  int handle(String message) => int.parse(message);
}

dynamic handleDynamic(dynamic message) {
  switch (message.runtimeType as Type) {
    case String:
      return 'string';
    case int:
      return 'integer';
    default:
      return -1;
  }
}

class CounterActor with Handler<void, int> {
  int count = 0;

  @override
  int handle(void message) => count++;
}

Future<void> sleepingActor(int message) async {
  await Future<dynamic>.delayed(Duration(milliseconds: message));
}

void main() {
  group('Typed Actor can run in isolate', () {
    Actor<String, int> actor;

    setUp(() {
      actor = Actor(IntParserActor());
    });

    test('can handle messages async', () async {
      expect(await actor.send('10'), equals(10));
    });
    test('error is propagated to caller', () {
      expect(actor.send('x'), throwsFormatException);
    });
  });

  group('Untyped Actor can run in isolate', () {
    Actor actor;

    setUp(() {
      actor = Actor<dynamic, dynamic>.of(handleDynamic);
    });

    test('can handle messages async', () async {
      expect(await actor.send(10), equals('integer'));
      expect(await actor.send('text'), equals('string'));
      expect(await actor.send(true), equals(-1));
    });
  });

  group('Actor can maintain internal state', () {
    Actor<void, int> actor;

    setUp(() {
      actor = Actor(CounterActor()..count = 4);
    });

    test('actor uses internal state to respond', () async {
      expect(await actor.send(null), equals(4));
      expect(await actor.send(null), equals(5));
      expect(await actor.send(null), equals(6));
    });
  });

  group('Actors really run in parallel', () {
    Actor<int, void> actor1;
    Actor<int, void> actor2;

    setUp(() {
      actor1 = Actor.of(sleepingActor);
      actor2 = Actor.of(sleepingActor);
    });

    test(
        'two actors can wait for 100 ms each, and in total '
        'we get a wait between 100 and 190', () async {
      final future1 = actor1.send(100);
      final future2 = actor2.send(100);
      final startTime = DateTime.now();
      await future1;
      await future2;
      expect(DateTime.now().difference(startTime).inMilliseconds,
          inInclusiveRange(100, 190));
    });
  });
}
