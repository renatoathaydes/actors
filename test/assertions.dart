import 'dart:async';

import 'package:actors/actors.dart';
import 'package:test/test.dart';

final isRemoteErrorException = TypeMatcher<RemoteErrorException>();

final isMessengerStreamBroken = TypeMatcher<MessengerStreamBroken>();

Matcher linesIncluding(List<Object> someExpectedLines) =>
    _RemoteErrorExceptionMatcher((lines) {
      for (final expected in someExpectedLines) {
        if (expected is RegExp) {
          final exp = expected;
          if (!lines.any((l) => exp.hasMatch(l))) {
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
    return _checkErrorMessageLines(item.toString().split('\n'));
  }
}

Future expectToThrow(FutureOr Function() action,
    {Matcher? matchException, Matcher? matchTrace}) async {
  try {
    await action();
    throw AssertionError('Expected action to throw, but it returned normally');
  } catch (e, t) {
    expect(e, matchException);
    if (matchTrace != null) expect(t.toString(), matchTrace);
  }
  return null;
}
