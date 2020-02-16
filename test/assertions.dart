import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

final isRemoteErrorException = TypeMatcher<RemoteErrorException>();

final isMessengerStreamBroken = TypeMatcher<MessengerStreamBroken>();

Matcher linesIncluding(List someExpectedLines) =>
    _RemoteErrorExceptionMatcher((lines) {
      for (var expected in someExpectedLines) {
        if (expected is RegExp) {
          if (!lines.any((l) => expected.hasMatch(l))) {
            return false;
          }
        } else if (!lines.contains(expected)) {
          return false;
        }
      }
      return true;
    });

class _RemoteErrorExceptionMatcher extends Matcher {
  final bool Function(List<String>) _checkErrorMessageLines;

  _RemoteErrorExceptionMatcher(this._checkErrorMessageLines);

  @override
  Description describe(Description description) =>
      StringDescription('does not match');

  @override
  bool matches(item, Map matchState) {
    return _checkErrorMessageLines(item.toString().split("\n"));
  }
}

Future expectToThrow(FutureOr action(),
    {Matcher matchException, Matcher matchTrace}) async {
  try {
    await action();
    throw AssertionError('Expected action to throw, but it returned normally');
  } catch (e, t) {
    expect(e, matchException);
    expect(t.toString(), matchTrace);
  }
  return null;
}

class _ExceptionWithStacktraceMatcher extends Matcher {
  @override
  Description describe(Description description) {
    // TODO: implement describe
    return null;
  }

  @override
  bool matches(item, Map matchState) {
    // TODO: implement matches
    return null;
  }
}
