import 'package:actors/actors.dart';
import 'package:test/test.dart';

class IntParserActor with Handler<String, int> {
  @override
  int handle(String message) => int.parse(message);
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
}
