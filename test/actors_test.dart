@Timeout(Duration(seconds: 1))
import 'dart:async';
import 'dart:io';

import 'package:actors/actors.dart';
import 'package:conveniently/conveniently.dart';
import 'package:path/path.dart' as paths;
import 'package:test/test.dart';

import '../example/stateful_actor_example.dart' as ex_stateful;
import 'assertions.dart';

class IntParserActor with Handler<String, int> {
  @override
  int handle(String message) => int.parse(message);
}

class TryIntParserActor with Handler<String, int?> {
  @override
  int? handle(String message) => int.tryParse(message);
}

Object handleDynamic(message) {
  return switch (message) {
    String _ => 'string',
    int _ => 'integer',
    AddSenderFunction fun => fun(),
    Function fun => fun(),
    _ => -1
  };
}

Stream<int> handleTyped(String message) async* {
  switch (message) {
    case 'good message':
      for (final item in [10, 20]) {
        yield item;
      }
      break;
    case 'throw':
      throw Exception('Bad message');
    case 'throw with stacktrace':
    default:
      // cause an Error intentionally
      message.substring(66);
      yield 0;
  }
}

Stream dynamicStream(value) async* {
  for (final i in [1, '#2', null, 3.0]) {
    yield i;
  }
}

class CounterActor with Handler<Symbol?, int> {
  int count;

  CounterActor([int initialCount = 0]) : count = initialCount;

  @override
  int handle(Symbol? message) {
    switch (message) {
      case #add:
        count++;
        break;
      case #sub:
        count--;
        break;
      case null:
        break;
      default:
        throw 'unexpected message';
    }
    return count;
  }
}

Future<void> sleepingActor(int message) async {
  await Future.delayed(Duration(milliseconds: message));
}

class FileWriterHandler with Handler<String, bool> {
  static File tempFile =
      File(paths.join(Directory.systemTemp.path, 'writer.txt'));

  @override
  FutureOr<bool> handle(String message) async {
    try {
      await tempFile.writeAsString(message, mode: FileMode.append);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  FutureOr<void> close() async {
    await handle('close');
  }
}

class ErrorMethods with Handler<String, Never> {
  @override
  FutureOr<Never> handle(String message) {
    switch (message) {
      case 'exception':
        _exception();
      case 'error':
        _error();
      default:
        throw 'unexpected message';
    }
  }

  Never _exception() {
    _nest();
  }

  Never _nest() {
    throw FormatException('always bad format');
  }

  Never _error() {
    throw ArgumentError.value('value is always wrong', 'none');
  }
}

class BadInitHandler with Handler<void, void> {
  @override
  FutureOr<void> init() async {
    await Future.delayed(const Duration(milliseconds: 10));
    throw FormatException('cannot initialize');
  }

  @override
  void handle(void message) {}
}

class AddSenderFunction {
  final Sendable<Symbol?, int> _sender;

  AddSenderFunction(this._sender);

  Future<int> call() {
    return _sender.send(#add);
  }
}

void main() {
  group('Typed Actor can run in isolate', () {
    late Actor<String, int> actor;

    setUp(() {
      actor = Actor(IntParserActor());
    });

    test('can handle messages async', () async {
      expect(await actor.send('10'), equals(10));
    });

    test('error is propagated to caller', () {
      expect(actor.send('x'), throwsFormatException);
    });
  });

  group('Typed Actor returning possibly null value can run in isolate', () {
    late Actor<String, int?> actor;

    setUp(() {
      actor = Actor.create(TryIntParserActor.new);
    });

    test('can handle messages async', () async {
      expect(await actor.send('10'), equals(10));
    });

    test('bad message results in null being returned', () async {
      expect(await actor.send('x'), isNull);
    });
  });

  group('Untyped Actor can run in isolate', () {
    late Actor actor;

    setUp(() {
      actor = Actor.of(handleDynamic);
    });

    test('can handle messages async', () async {
      expect(await actor.send(10), equals('integer'));
      expect(await actor.send('text'), equals('string'));
      expect(await actor.send(true), equals(-1));
    });

    test('can call sent function', () async {
      expect(await actor.send(() => 24), equals(24));
    });

    test('can send Sendable to Actor', () async {
      final thirdActor = Actor(CounterActor(9));
      final thirdSender = await thirdActor.toSendable();
      try {
        expect(await actor.send(AddSenderFunction(thirdSender)), equals(10));
      } finally {
        await thirdActor.close();
      }
    });
  });

  group('Actor can maintain internal state', () {
    late Actor<Symbol?, int> actor;
    final localCounter = CounterActor(4);

    setUp(() {
      actor = Actor(localCounter);
    });

    test('actor uses internal state to respond', () async {
      expect(await actor.send(null), equals(4));
      expect(await actor.send(#add), equals(5));

      // make sure the local actor instance's state is not affected
      expect(localCounter.count, equals(4));

      expect(await actor.send(#add), equals(6));
      expect(await actor.send(#sub), equals(5));
    });

    // include the stateful actor example in this group
    ex_stateful.main();
  });

  group('Actor Handler is closed', () {
    late Actor<String, bool> actor;
    setUp(() async {
      if (await FileWriterHandler.tempFile.exists()) {
        await FileWriterHandler.tempFile.delete();
      }
      actor = Actor.create(FileWriterHandler.new);
    });
    test('when the Actor closes', () async {
      expect(await actor.send('hello-'), isTrue);
      await actor.close();
      final fileContents = await FileWriterHandler.tempFile.readAsString();
      expect(fileContents, equals('hello-close'));
    });
  });

  group('Actors problems', () {
    late Actor<String, void> actor;
    setUp(() {
      actor = Actor.create(ErrorMethods.new);
    });
    test('Exceptions are propagated to caller', () async {
      await expectToThrow(
        () async => await actor.send('exception'),
        matchException: isA<FormatException>(),
        matchTrace: linesIncluding([
          RegExp('.* ErrorMethods._nest.*'),
          RegExp('.*ErrorMethods._exception.*'),
        ]),
      );
    });
    test('Errors are propagated to caller', () async {
      await expectToThrow(
        () => actor.send('error'),
        matchException: isA<RemoteErrorException>().having(
            (e) => e.errorAsString,
            'errorAsString',
            contains('value is always wrong')),
        matchTrace: linesIncluding([
          RegExp('.*ErrorMethods._error.*'),
        ]),
      );
    });
    test(
        'Errors during init cause all Actor actions to throw ActorInitializationException',
        () async {
      final badActor = Actor.create(BadInitHandler.new);
      // try twice to ensure that every call to send fails, not just the first
      await 2.times(() async {
        await expectToThrow(() => badActor.send(null),
            matchException: isA<ActorInitializationException>()
                .having((e) => e.cause, 'cause', isA<FormatException>()));
      });
    });
  });

  group('Actors closed while processing message', () {
    late Actor<int, void> actor;
    setUp(() {
      actor = Actor.of(sleepingActor);
    });
    test('should throw on call site', () async {
      final response = actor.send(500);
      await Future.delayed(Duration(milliseconds: 250));

      // avoids causing errors due to unhandled Future errors
      // (will await Future later)
      runZonedGuarded(actor.close, (error, stack) {});
      expect(() => response, throwsA(isMessengerStreamBroken));
    });
  });

  group('Actors really run in parallel', () {
    late List<Actor<int, void>> actors;

    setUp(() {
      actors = Iterable.generate(5, (_) => Actor.of(sleepingActor)).toList();
    });

    test(
        'many actors wait for 100 ms each, and in total '
        'we get a wait time that is less than if they all ran sync', () async {
      final sleepTime = 100;
      final futures = actors.map((actor) => actor.send(sleepTime)).toList();
      final watch = Stopwatch()..start();
      for (final future in futures) {
        await future;
      }
      watch.stop();
      final totalTimeIfRunInSeries = sleepTime * actors.length;

      // we know at least one Actor ran in parallel if the time it took to
      // wait for all futures is a little less than the theoretical minimal
      // if they had run in series
      expect(watch.elapsedMilliseconds,
          inInclusiveRange(sleepTime, totalTimeIfRunInSeries - 10));
    }, retry: 1);
  });

  group('StreamActors can return Stream', () {
    StreamActor? actor;
    StreamActor<String, int>? typedActor;
    tearDown(() async {
      await actor?.close();
      await typedActor?.close();
    });

    test('of dynamic type', () async {
      actor = StreamActor.of(dynamicStream);
      final answers = [];
      var stream = actor!.send(null);
      await for (final message in stream) {
        answers.add(message);
      }
      expect(answers, equals([1, '#2', null, 3.0]));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('with typed values', () async {
      typedActor = StreamActor<String, int>.of(handleTyped);
      final answers = <int>[];
      var stream = typedActor!.send('good message');
      await for (final message in stream) {
        answers.add(message);
      }
      expect(answers, equals([10, 20]));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('with typed values (repeated execution with error between)', () async {
      typedActor = StreamActor<String, int>.of(handleTyped);
      Future<List<int>> sendGoodMessage() =>
          typedActor!.send('good message').toList();
      final answers = <int>[];
      answers.addAll(await sendGoodMessage());
      answers.addAll(await sendGoodMessage());
      expect(() => typedActor!.send('throw').toList(), throwsA(isException));
      answers.addAll(await sendGoodMessage());
      answers.addAll(await sendGoodMessage());
      expect(answers, equals([10, 20, 10, 20, 10, 20, 10, 20]));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('with typed values (error is propagated)', () {
      typedActor = StreamActor<String, int>.of(handleTyped);
      expect(
          typedActor!.send('throw').first,
          throwsA(isException.having((error) => error.toString(),
              'expected error message', equals('Exception: Bad message'))));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('with typed values (stacktrace error is propagated)', () async {
      typedActor = StreamActor<String, int>.of(handleTyped);
      await expectToThrow(() => typedActor!.send('throw with stacktrace').first,
          matchException: isRemoteErrorException.having(
              (e) => e.errorAsString,
              'expected error message',
              linesIncluding([
                'RangeError (start): Invalid value: Not in inclusive range 0..21: 66',
              ])),
          matchTrace: linesIncluding([
            // needs to contain the function that threw in the remote Isolate
            RegExp('.*handleTyped \\(file:.*'),
            // and the package and function that handles remote messages
            RegExp('.*_sendAnswer \\(package:actors.*'),
          ]));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('can be closed while streaming', () async {
      typedActor = StreamActor<String, int>.of(handleTyped);
      final answers = <int>[];
      answers.addAll(await typedActor!.send('good message').toList());
      final stream = typedActor!.send('good message').asBroadcastStream();
      answers.add(await stream.first);
      await typedActor!.close();
      expect(answers, equals([10, 20, 10]));
      expect(
          stream.first,
          throwsA(isStateError.having(
              (e) => e.message, 'error message', equals('No element'))));
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
