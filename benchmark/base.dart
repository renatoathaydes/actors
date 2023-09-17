import 'dart:async';

import 'package:benchmark_harness/benchmark_harness.dart';

abstract class MessageBench<M, A> extends AsyncBenchmarkBase {
  int _sentMessages = 0;

  MessageBench(String name) : super(name);

  int get sentMessages => _sentMessages;

  Future<A> send(M message);

  Future<void> stop();

  M nextMessage();

  FutureOr<void> checkFinalMessage(A answer);

  FutureOr<A> _sendMessage() {
    final message = nextMessage();
    _sentMessages++;
    return send(message);
  }

  @override
  Future<void> warmup() async {
    await _sendMessage();
  }

  @override
  Future<void> run() async {
    await _sendMessage();
  }

  @override
  Future<void> teardown() async {
    final answer = await _sendMessage();
    await stop();
    await checkFinalMessage(answer);
  }
}
