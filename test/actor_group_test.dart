import 'package:actors/actors.dart';
import 'package:test/test.dart';

class Two with Handler<int, int> {
  @override
  int handle(int message) => message * 2;
}

void main() {
  group('ActorGroup can handle messages like a single Actor', () {
    ActorGroup actorGroup;

    setUp(() {
      actorGroup = ActorGroup(Two());
    });

    test('ActorGroup handles messages like single Actor', () async {
      expect(await actorGroup.send(2), equals(4));
      expect(await actorGroup.send(10), equals(20));
      expect(await actorGroup.send(25), equals(50));
    });
  });
}
