import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

class _CompletableCounter {
  int _value = 0;
  final int? completesAt;
  final _completer = Completer();

  _CompletableCounter({this.completesAt});

  void inc() {
    _value++;
    if (_value == completesAt) {
      _completer.complete(null);
    }
  }

  Future get future => _completer.future;
}

typedef _MakesHandler = int Function(int) Function(int);

void main() {
  group('MultiHandler', () {
    test('should respect the documented policy to forward and compute answers',
        () async {
      final defaultStrategy = MultiHandler<int, int>();
      var counter1 = 0;
      var counter2 = 0;
      var counter3 = 0;
      var counter4 = 0;

      final completer = _CompletableCounter(completesAt: 4);

      // ignore: omit_local_variable_types
      _MakesHandler handlerIncrementing = (int counterIndex) {
        return (n) {
          switch (counterIndex) {
            case 0:
              counter1++;
              break;
            case 1:
              counter2++;
              break;
            case 2:
              counter3++;
              break;
            case 3:
              counter4++;
          }
          completer.inc();
          return n + 1;
        };
      };

      final messengers = Iterable.generate(
          4, (index) => LocalMessenger.of(handlerIncrementing(index)));

      final handle = defaultStrategy.toHandler(messengers.toList());

      final answer1 = await handle(1);

      // only 2 messengers should have been called so far
      expect(
          [counter1, counter2, counter3, counter4].where((c) => c == 1).length,
          equals(2));
      expect(
          [counter1, counter2, counter3, counter4].where((c) => c == 0).length,
          equals(2));

      // await until all messengers have been called
      await completer.future;

      // now, all counters were called
      expect([counter1, counter2, counter3, counter4], equals([1, 1, 1, 1]));

      // and the answer is right
      expect(answer1, equals(2));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('should follow custom policy to forward and compute answers',
        () async {
      final customStrategy = MultiHandler<int, int>(
          minAnswers: 3,
          handlersPerMessage: 3,
          combineAnswers: (answers) => answers.fold(0, (a, b) => a + b));

      var counter1 = 0;
      var counter2 = 0;
      var counter3 = 0;
      var counter4 = 0;

      // this should timeout as only 3 messengers will be called
      final completer = _CompletableCounter(completesAt: 4);

      // ignore: omit_local_variable_types
      _MakesHandler handlerIncrementing = (int counterIndex) {
        return (n) {
          switch (counterIndex) {
            case 0:
              counter1++;
              break;
            case 1:
              counter2++;
              break;
            case 2:
              counter3++;
              break;
            case 3:
              counter4++;
          }
          completer.inc();
          return n + counterIndex + 1;
        };
      };

      final messengers = Iterable.generate(4,
          (index) => LocalMessenger<int, int>.of(handlerIncrementing(index)));

      final handle = customStrategy.toHandler(messengers.toList());

      final answer1 = await handle(5);

      // 3 messengers should have been called
      expect(
          [counter1, counter2, counter3, counter4].where((c) => c == 1).length,
          equals(3));
      expect(
          [counter1, counter2, counter3, counter4].where((c) => c == 0).length,
          equals(1));

      // and the answer is combined appropriately
      var expectedAnswer = 0;
      if (counter1 > 0) expectedAnswer += 6;
      if (counter2 > 0) expectedAnswer += 7;
      if (counter3 > 0) expectedAnswer += 8;
      if (counter4 > 0) expectedAnswer += 9;

      expect(answer1, equals(expectedAnswer));

      // and no more calls happen
      final result = await completer.future
          .timeout(Duration(milliseconds: 100), onTimeout: () => #timeout);
      expect(result, equals(#timeout));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('should succeed even if some messengers fail when m > n', () async {
      final customStrategy = MultiHandler<int, int>(
          minAnswers: 3,
          handlersPerMessage: 4,
          combineAnswers: (answers) => answers.fold(0, (a, b) => a + b));

      var counter1 = 0;
      var counter2 = 0;
      var counter3 = 0;
      var counter4 = 0;

      final completer = _CompletableCounter(completesAt: 4);

      // ignore: omit_local_variable_types
      _MakesHandler handlerIncrementing = (int counterIndex) {
        return (n) {
          switch (counterIndex) {
            case 0:
              counter1++;
              break;
            case 1:
              counter2++;
              break;
            case 2:
              counter3++;
              break;
            case 3:
              counter4++;
              completer.inc();
              throw Exception('this actor is dead');
          }
          completer.inc();
          return n + counterIndex + 1;
        };
      };

      final messengers = Iterable.generate(4,
          (index) => LocalMessenger<int, int>.of(handlerIncrementing(index)));

      final handle = customStrategy.toHandler(messengers.toList());

      final answer1 = await handle(5);

      await completer.future;

      // all 4 messengers should have been called
      expect(
          [counter1, counter2, counter3, counter4].where((c) => c == 1).length,
          equals(4));

      // and the answer is combined appropriately
      var expectedAnswer = 6 + 7 + 8;
      expect(answer1, equals(expectedAnswer));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('should fail if x messengers fail where x > n', () async {
      final customStrategy = MultiHandler<int, int>(minAnswers: 3);

      // ignore: omit_local_variable_types
      _MakesHandler handlerIncrementing = (int counterIndex) {
        return (n) {
          // throws on indexes 1 and 3, passes on 0 and 2, so it'll never
          // achieve 3 acks
          if (n % 2 != 0) throw "don't wanna do it";
          return n;
        };
      };

      final messengers = Iterable.generate(4,
          (index) => LocalMessenger<int, int>.of(handlerIncrementing(index)));

      final handle = customStrategy.toHandler(messengers.toList());

      expect(() => handle(1), throwsA(equals("don't wanna do it")));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('does not allow minAnswers > handlersPerMessage', () {
      expect(
          () => MultiHandler<int, int>(handlersPerMessage: 3, minAnswers: 4),
          throwsA(isArgumentError.having((e) => e.message, 'error message',
              equals('minAnswers > handlersPerMessage (4 > 3)'))));
    });
  });
}
