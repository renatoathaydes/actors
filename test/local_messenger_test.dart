import 'package:actors/actors.dart';
import 'package:test/test.dart';

class Counter with Handler<int, int> {
  var count = 0;

  @override
  int handle(int message) => count += message;
}

void main() {
  group('LocalMessenger can run in locally', () {
    late LocalMessenger<int, int> messenger;
    late Counter counter;

    setUp(() {
      counter = Counter();
      messenger = LocalMessenger(counter);
    });

    test('can handle messages async, but locally', () async {
      expect(await messenger.send(1), equals(1));
      expect(counter.count, equals(1));

      expect(await messenger.send(5), equals(6));
      expect(counter.count, equals(6));
    });
  });
}
