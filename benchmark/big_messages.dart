import 'dart:async';
import 'dart:isolate';

import 'package:actors/actors.dart' show Actor, Handler;
import 'package:collection/collection.dart';
import 'package:conveniently/conveniently.dart' show ConvenientlyInt;

import 'base.dart';

final class _BigMessage {
  final List<int> numbers;
  final Set<String> strings;
  final double count;
  final double doubleCount;

  _BigMessage(this.numbers, this.strings, this.count, this.doubleCount);

  static _BigMessage next(int count) => _BigMessage(
      List.generate(10, (i) => i),
      List.generate(10, (i) => i.toString()).toSet(),
      count.toDouble(),
      2.0 * count);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BigMessage &&
          const ListEquality().equals(numbers, other.numbers) &&
          const SetEquality().equals(strings, other.strings) &&
          count == other.count &&
          doubleCount == other.doubleCount;

  @override
  int get hashCode =>
      numbers.hashCode ^
      strings.hashCode ^
      count.hashCode ^
      doubleCount.hashCode;

  @override
  String toString() {
    return '_BigMessage{numbers: $numbers, '
        'strings: $strings, '
        'count: $count, '
        'doubleCount: $doubleCount}';
  }
}

final class _BigMessageHandler with Handler<_BigMessage, _BigMessage> {
  int _count;

  _BigMessageHandler([this._count = 0]);

  @override
  Future<_BigMessage> handle(_BigMessage message) async {
    _count++;
    final count = message.count + _count;
    return _BigMessage(message.numbers.map((e) => e + 1).toList(),
        message.strings.map((s) => 'x$s').toSet(), count, 2.0 * count);
  }
}

abstract class _BigMessageBench extends MessageBench<_BigMessage, _BigMessage> {
  _BigMessageBench(super.name);

  @override
  _BigMessage nextMessage() {
    return _BigMessage.next(sentMessages);
  }

  @override
  Future<void> checkFinalMessage(_BigMessage message) async {
    final expectedMessage = await _BigMessageHandler(sentMessages - 1)
        .handle(_BigMessage.next(sentMessages - 1));
    if (expectedMessage != message) {
      throw Exception('Expected final message to be $expectedMessage'
          ' but was $message');
    }
  }
}

final ReceivePort _isolateReceivePort = ReceivePort();
SendPort? _isolateResponder;
final _isolateCounter = _BigMessageHandler();

void _isolateMain(message) async {
  if (_isolateResponder == null) {
    _isolateReceivePort.listen(_isolateMain);
    _isolateResponder = message;
    _isolateResponder!.send(_isolateReceivePort.sendPort);
  } else {
    // not doing error handling intentionally to check absolute minimal overhead
    final answer = await _isolateCounter.handle(message);
    _isolateResponder!.send(answer);
  }
}

final class _BigMessageIsolateBench extends _BigMessageBench {
  late final Isolate _isolate;
  late final SendPort _messageSender;
  late final Stream _answerWaiter;
  final receivePort = ReceivePort();

  _BigMessageIsolateBench() : super('Isolate big message roundtrip');

  @override
  Future<void> setup() async {
    _isolate = await Isolate.spawn(_isolateMain, receivePort.sendPort);
    _answerWaiter = receivePort.asBroadcastStream();
    _messageSender = await _answerWaiter.first;
  }

  @override
  Future<_BigMessage> send(_BigMessage message) async {
    _messageSender.send(message);
    return await _answerWaiter.first;
  }

  @override
  Future<void> stop() async {
    _isolate.kill(priority: Isolate.immediate);
    receivePort.close();
  }
}

final class _BigMessageBasicAsyncBench extends _BigMessageBench {
  late final Handler<_BigMessage, _BigMessage> _handler;

  _BigMessageBasicAsyncBench() : super('Dart async big message roundtrip');

  @override
  Future<void> setup() async {
    _handler = _BigMessageHandler();
    await _handler.init();
  }

  @override
  Future<_BigMessage> send(_BigMessage message) async {
    return await _handler.handle(message);
  }

  @override
  Future<void> stop() async {
    await _handler.close();
  }
}

final class _BigMessageActorBench extends _BigMessageBench {
  late final Actor<_BigMessage, _BigMessage> _actor;

  _BigMessageActorBench() : super('Actor big message roundtrip');

  @override
  Future<void> setup() async {
    _actor = Actor(_BigMessageHandler());
  }

  @override
  Future<_BigMessage> send(_BigMessage message) async {
    return await _actor.send(message);
  }

  @override
  Future<void> stop() async {
    await _actor.close();
  }
}

Future<void> main() async {
  const runs = 3;
  await runs.times(() => _BigMessageBasicAsyncBench().report());
  await runs.times(() => _BigMessageIsolateBench().report());
  await runs.times(() => _BigMessageActorBench().report());
}
