import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

class ActorHasActor with Handler<int, int> {
  final Sendable<int, int> otherActor;

  ActorHasActor(this.otherActor);

  @override
  Future<int> handle(int message) async {
    return otherActor.send(message + 1);
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
    late Actor<int, int> otherActor;

    setUp(() async {
      mainActor = Actor(MainActor());
      otherActor = Actor(ActorHasActor(await mainActor.toSendable()));
    });

    tearDown(() {
      mainActor.close();
      otherActor.close();
    });

    test('can send msg to actor that sends msg to another actor', () async {
      expect(await otherActor.send(2), equals(3));
      expect(await otherActor.send(4), equals(8));
      expect(await mainActor.send(1), equals(9));
    }, timeout: const Timeout(Duration(seconds: 1)));
  });
}
