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
    Future<Message> futureAnswer, Completer<A> completer) {
  futureAnswer.then((Message answer) {
    if (answer.isError) {
      // if the answer is an error, its content will never be null
      completer.completeError(answer.content!, answer.stacktrace);
    } else {
      completer.complete(answer.content as A);
    }
  }, onError: (e, StackTrace stackTrace) {
    // the only way to get an error here is for the future to be killed
    completer.completeError(const MessengerStreamBroken(), stackTrace);
  });
  return completer.future;
}
