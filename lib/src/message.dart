import 'stub_actor.dart'
    if (dart.library.io) 'isolate/isolate_actor.dart'
    if (dart.library.html) 'web_worker/web_worker_actor.dart';

sealed class AnyMessage {}

enum TerminateActor implements AnyMessage {
  singleton;
}

final class Message implements AnyMessage {
  final num id;
  final Object? content;
  final String? stackTraceString;

  const Message(this.id, this.content, {this.stackTraceString});

  StackTrace? get stacktrace => stackTraceString != null
      ? StackTrace.fromString(stackTraceString!)
      : null;

  bool get isError => stackTraceString != null;

  @override
  String toString() {
    if (isError) {
      return 'Message{id=$id, error=$content, stackTrace=$stackTraceString}';
    }
    return 'Message{id=$id, content: $content}';
  }
}

final class OneOffMessage implements AnyMessage {
  final Sender sender;
  final Object? content;

  const OneOffMessage(this.sender, this.content);

  @override
  String toString() {
    return 'OneOffMessage{sender: $sender, content: $content}';
  }
}
