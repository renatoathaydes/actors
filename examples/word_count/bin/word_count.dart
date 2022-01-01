import 'dart:async';
import 'dart:io';

import 'package:actors/actors.dart';

class WordCount with Handler<File, int> {
  static final wordBoundary = RegExp("\\b");
  static final word = RegExp("\\w");

  @override
  Future<int> handle(File file) async {
    return (await file.readAsLines())
        .map((line) => line.split(wordBoundary).where(word.hasMatch).length)
        .fold<int>(0, (prev, count) => prev + count);
  }
}

Messenger<File, int> create(String option) {
  switch (option) {
    case "group":
      return ActorGroup(WordCount(), size: Platform.numberOfProcessors);
    case "actor":
      return Actor(WordCount());
    case "local":
      return LocalMessenger(WordCount());
    default:
      throw Exception('Unknown option: $option');
  }
}

void main(List<String> args) async {
  final argsIter = args.iterator;
  if (!argsIter.moveNext()) {
    throw Exception('no args');
  }

  final actor = create(argsIter.current);

  var total = 0;
  try {
    while (argsIter.moveNext()) {
      total += await wordCount(actor, argsIter.current);
    }
    print('$total');
  } finally {
    actor.close();
  }
}

FutureOr<int> wordCount(Messenger<File, int> messenger, String path) async {
  final futures = <FutureOr<int>>[];
  if (await FileSystemEntity.isFile(path)) {
    final file = File(path);
    futures.add(messenger.send(file));
  } else {
    if (await FileSystemEntity.isDirectory(path)) {
      final dir = Directory(path);
      await for (var child in dir.list(recursive: true)) {
        if (child is File) {
          futures.add(messenger.send(child));
        }
      }
    }
  }
  var result = 0;
  for (final future in futures) {
    result += await future;
  }
  return result;
}
