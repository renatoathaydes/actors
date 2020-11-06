import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

import 'assertions.dart';

class IntParserActor with Handler<String, int> {
  @override
  int handle(String message) => int.parse(message);
}

Object handleDynamic(message) {
  switch (message.runtimeType) {
    case String:
      return 'string';
    case int:
      return 'integer';
    default:
      return -1;
  }
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
    default:
      String? s;
      s!.trim(); // throw with stacktrace!!
  }
}

Stream dynamicStream(value) async* {
  for (final i in [1, '#2', 3.0]) {
    yield i;
  }
}

class CounterActor with Handler<Symbol, int> {
  int count = 0;

  @override
  int handle(Symbol message) => count++;
}

Future<Symbol> sleepingActor(int message) async {
  await Future.delayed(Duration(milliseconds: message));
  return #nothing;
}

class ErrorMethods with Handler<String, Symbol> {
  @override
  FutureOr<Symbol> handle(String message) {
    switch (message) {
      case 'exception':
        _exception();
      case 'error':
        _error();
    }
    return #unreachable;
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
  });

  group('Actor can maintain internal state', () {
    late Actor<void, int> actor;

    setUp(() {
      actor = Actor(CounterActor()..count = 4);
    });

    test('actor uses internal state to respond', () async {
      expect(await actor.send(null), equals(4));
      expect(await actor.send(null), equals(5));
      expect(await actor.send(null), equals(6));
    });
  });

  group('Actors problems', () {
    late Actor<String, void> actor;
    setUp(() {
      actor = Actor(ErrorMethods());
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
        () async => await actor.send('error'),
        matchException: isA<RemoteErrorException>().having(
            (e) => e.errorAsString,
            'errorAsString',
            contains('value is always wrong')),
        matchTrace: linesIncluding([
          RegExp('.*ErrorMethods._error.*'),
        ]),
      );
    });
  });

  group('Actors closed while processing message', () {
    late Actor<int, void> actor;
    setUp(() {
      actor = Actor.of(sleepingActor);
    });
    test('should throw on call site', () async {
      final response = actor.send(250);
      await Future.delayed(Duration(milliseconds: 150));
      await actor.close();
      expect(() async => await response, throwsA(isMessengerStreamBroken));
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
      var stream = await actor!.send(#start);
      await for (final message in stream) {
        answers.add(message);
      }
      expect(answers, equals([1, '#2', 3.0]));
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
      final sendGoodMessage = () => typedActor!.send('good message').toList();
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
                "NoSuchMethodError: The method 'trim' was called on null.",
              ])),
          matchTrace: linesIncluding([
            // needs to contain the function that threw in the remote Isolate
            RegExp('.*handleTyped \\(file:.*'),
            // and the package and function that handles remote messages
            RegExp('.*_remote \\(package:actors.*'),
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
