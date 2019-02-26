import 'package:actors/actors.dart';
import 'package:test/test.dart';

class IntParserActor with Handler<String, int> {
  @override
  int handle(String message) => int.parse(message);
}

class DynamicActor with Handler {
  @override
  handle(message) {
    switch (message.runtimeType) {
      case String:
        return 'string';
      case int:
        return 'integer';
      default:
        return -1;
    }
  }
}

class CounterActor with Handler<void, int> {
  int count = 0;

  @override
  int handle(void message) => count++;
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
      actor = Actor(DynamicActor());
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
}
