import 'dart:async';

import 'message.dart';

/// An Exception that indicates that the channel of communication with a
/// [Messenger] has been broken.
///
/// This typically occurs when an [Actor] is closed while it still has pending
/// messages being processed.
class MessengerStreamBroken implements Exception {
  const MessengerStreamBroken();
}

/// This is an internal function.
Future<A> handleAnswer<A>(
    Future<void> senderFuture, Future<Message> futureAnswer) async {
  try {
    await senderFuture;
  } catch (e) {
    // when the sender fails, suppress the answer Future's expected failure
    await futureAnswer.then((value) => null, onError: (_) => null);
    rethrow;
  }
  final answer = await futureAnswer;
  if (answer.isError) {
    if (answer.content == const MessengerStreamBroken()) {
      throw const MessengerStreamBroken();
    }
    Error.throwWithStackTrace(answer.content!, answer.stacktrace!);
  }
  return answer.content as A;
}
