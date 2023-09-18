import 'dart:async';
import 'dart:isolate';

import 'package:actors/actors.dart' show Actor, Handler;
import 'package:conveniently/conveniently.dart' show ConvenientlyInt;

import 'base.dart';

enum _CounterMessage {
  inc,
  dec;

  _CounterMessage next() => switch (this) { inc => dec, dec => inc };
}

final class _CounterActor with Handler<_CounterMessage, int> {
  int count = 0;

  _CounterActor();

  @override
  int handle(_CounterMessage message) {
    return switch (message) {
      _CounterMessage.inc => ++count,
      _CounterMessage.dec => --count
    };
  }
}

abstract class _SmallMessageBench extends MessageBench<_CounterMessage, int> {
  var _message = _CounterMessage.dec;

  _SmallMessageBench(super.name);

  @override
  _CounterMessage nextMessage() {
    _message = _message.next();
    return _message;
  }

  @override
  void checkFinalMessage(int message) {
    final expectedMessage = sentMessages % 2 == 0 ? 0 : 1;
    if (expectedMessage != message) {
      throw Exception('Expected final message to be $expectedMessage'
          ' but was $message');
    }
  }
}

final ReceivePort _isolateReceivePort = ReceivePort();
SendPort? _isolateResponder;
final _isolateCounter = _CounterActor();

void _isolateMain(message) {
  if (_isolateResponder == null) {
    _isolateReceivePort.listen(_isolateMain);
    _isolateResponder = message;
    _isolateResponder!.send(_isolateReceivePort.sendPort);
  } else {
    final answer = _isolateCounter.handle(message);
    _isolateResponder!.send(answer);
  }
}

final class _SmallMessageIsolateBench extends _SmallMessageBench {
  late final Isolate _isolate;
  late final SendPort _messageSender;
  late final Stream _answerWaiter;
  final receivePort = ReceivePort();

  _SmallMessageIsolateBench() : super('Isolate small message roundtrip');

  @override
  Future<void> setup() async {
    _isolate = await Isolate.spawn(_isolateMain, receivePort.sendPort);
    _answerWaiter = receivePort.asBroadcastStream();
    _messageSender = await _answerWaiter.first;
  }

  @override
  Future<int> send(_CounterMessage message) async {
    _messageSender.send(message);
    return await _answerWaiter.first;
  }

  @override
  Future<void> stop() async {
    _isolate.kill(priority: Isolate.immediate);
    receivePort.close();
  }
}

final class _SmallMessageBasicAsyncBench extends _SmallMessageBench {
  late final Handler<_CounterMessage, int> _handler;

  _SmallMessageBasicAsyncBench() : super('Dart async small message roundtrip');

  @override
  Future<void> setup() async {
    _handler = _CounterActor();
    await _handler.init();
  }

  @override
  Future<int> send(_CounterMessage message) async {
    return await _handler.handle(message);
  }

  @override
  Future<void> stop() async {
    await _handler.close();
  }
}

final class _SmallMessageActorBench extends _SmallMessageBench {
  late final Actor<_CounterMessage, int> _actor;

  _SmallMessageActorBench() : super('Actor small message roundtrip');

  @override
  Future<void> setup() async {
    _actor = Actor.create(_CounterActor.new);
  }

  @override
  Future<int> send(_CounterMessage message) async {
    return await _actor.send(message);
  }

  @override
  Future<void> stop() async {
    await _actor.close();
  }
}

Future<void> main() async {
  const runs = 3;
  await runs.times(() => _SmallMessageBasicAsyncBench().report());
  await runs.times(() => _SmallMessageIsolateBench().report());
  await runs.times(() => _SmallMessageActorBench().report());
}
