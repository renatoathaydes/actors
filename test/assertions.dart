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
