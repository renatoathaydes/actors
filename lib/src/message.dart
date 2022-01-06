class Message {
  final int id;
  final Object? content;
  final String? stackTraceString;

  const Message(this.id, this.content, {this.stackTraceString});

  StackTrace? get stacktrace => stackTraceString != null
      ? StackTrace.fromString(stackTraceString!)
      : null;

  bool get isError => stackTraceString != null;
}
