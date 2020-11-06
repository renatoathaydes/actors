import 'dart:async';

import 'actors_base.dart';

/// A strategy for forwarding messages and selecting or computing an answer
/// from a group of [Messenger] instances.
///
/// Typically used with the [ActorGroup] class.
abstract class GroupStrategy<M, A> {
  const GroupStrategy();

  /// Get a [HandlerFunction] that uses this strategy to forward messages
  /// to the provided [messengers], returning a single answer that may
  /// be either provided by one of the given messengers, or computed
  /// by combining in some way the answers given by the messengers.
  HandlerFunction<M, A> toHandler(List<Messenger<M, A>> messengers);
}

class _MultiCompleter<A> {
  final List<A> _answers = [];
  final int _requiredCompletions;
  final int _maxPossibleCompletions;
  final Completer<List<A>> _completer = Completer();
  int _errorCount = 0;

  _MultiCompleter(this._requiredCompletions, this._maxPossibleCompletions);

  void complete(A value) {
    if (_completer.isCompleted) return;
    _answers.add(value);
    if (_answers.length >= _requiredCompletions) {
      _completer.complete(_answers);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) return;
    _errorCount++;
    final actorsLeft = _maxPossibleCompletions - _answers.length - _errorCount;
    if (actorsLeft <= 0) {
      _completer.completeError(error, stackTrace);
    }
  }

  Future<List<A>> get future => _completer.future;
}

/// [GroupStrategy] that sends each message received to `handlersPerMessage`
/// (m) [Messenger]s, and requires 'minAnswers' (n) successful answers to
/// provide a final, combined answer, where `group size >= m >= n`.
///
/// The handlers for each message are currently chosen randomly from the
/// available group's messengers each time a message is sent,
/// but this behaviour may change in the future.
class MultiHandler<M, A> extends GroupStrategy<M, A> {
  final int minAnswers;
  final int? handlersPerMessage;
  final A Function(List<A>) combineAnswers;

  /// Creates a [MultiHandler] with:
  ///
  /// * [minAnswers] - number of successful answers that should be awaited for.
  /// * [handlersPerMessage] - number of [Messenger]s that should receive each message (defaults to all).
  /// * [combineAnswers] - how to combine the received answers to provide a single answer.
  ///
  /// The value of [minAnswers] must be less than or equal to that of [handlersPerMessage].
  ///
  /// The default [combineAnswers] function returns the first answer if all
  /// answers are equal, and throws an [Exception] if received answers differ.
  MultiHandler(
      {this.minAnswers = 2,
      this.handlersPerMessage,
      A Function(List<A>)? combineAnswers})
      : combineAnswers = combineAnswers ?? _firstAnswerIfAllEqual {
    final _handlersPerMessage = handlersPerMessage;
    if (_handlersPerMessage != null && minAnswers > _handlersPerMessage) {
      throw ArgumentError(
          'minAnswers > handlersPerMessage ($minAnswers > $_handlersPerMessage)');
    }
  }

  static T _firstAnswerIfAllEqual<T>(List<T> answers) {
    final firstAnswer = answers[0];
    final ok = answers.skip(1).every((answer) => answer == firstAnswer);
    if (ok) return firstAnswer;
    throw Exception('Inconsistent answers received from different '
        'Actors in the group');
  }

  @override
  HandlerFunction<M, A> toHandler(List<Messenger<M, A>> messengers) {
    if (messengers.length < minAnswers) {
      throw ArgumentError('Cannot create HandlerFunction with '
          'messengers.length < minAnswers:'
          ' (${messengers.length} < $minAnswers)');
    }
    final handlersToCall = handlersPerMessage ?? messengers.length;
    if (messengers.length < handlersToCall) {
      throw ArgumentError('Cannot create HandlerFunction with '
          'messengers.length < handlersPerMessage:'
          ' (${messengers.length} < $handlersPerMessage)');
    }
    return (M message) {
      final completer = _MultiCompleter<A>(minAnswers, handlersToCall);
      final futures = _pickMessengers(messengers, handlersToCall)
          .map((m) => m.send(message));
      for (final future in futures) {
        if (future is Future<A>) {
          future.then(completer.complete, onError: completer.completeError);
        }
      }
      return completer.future.then(combineAnswers);
    };
  }

  Iterable<Messenger<M, A>> _pickMessengers(
      List<Messenger<M, A>> messengers, int handlersToCall) {
    final all = messengers.toList(growable: false);
    all.shuffle();
    return all.take(handlersToCall);
  }
}

/// [GroupStrategy] that sends a message to a single member of the group,
/// iterating over all members as messages are sent.
class RoundRobin<M, A> extends GroupStrategy<M, A> {
  const RoundRobin() : super();

  @override
  HandlerFunction<M, A> toHandler(List<Messenger<M, A>> messengers) {
    var index = 0;
    var size = messengers.length;
    return (M message) => messengers[index++ % size].send(message);
  }
}

class _Group<M, A> {
  final List<Messenger<M, A>> _actors;
  final HandlerFunction<M, A> _handle;

  _Group(this._actors, GroupStrategy<M, A> strategy)
      : _handle = strategy.toHandler(_actors);

  FutureOr<A> handle(M message) => _handle(message);

  FutureOr<void> close() async {
    for (final actor in _actors) {
      await actor.close();
    }
  }
}

/// An [ActorGroup] groups a number of [Actor]s using the same type of
/// [Handler] to handle messages.
///
/// Notice that each [Actor] will have its own instance of the [Handler],
/// and because of that the [Handler]s cannot share any state.
///
/// When a message is sent to an [ActorGroup] it may be handled by
/// any of the [Actor]s in the group, or by many depending on the chosen
/// [GroupStrategy].
///
/// Each [Actor] runs, as usual, in its own [Isolate].
class ActorGroup<M extends Object, A extends Object> with Messenger<M, A> {
  final int size;
  final _Group<M, A> _group;

  /// Creates an [ActorGroup] with the given [size] that handles messages
  /// using the given [Handler].
  ///
  /// A [GroupStrategy] may be provided, defaulting to [RoundRobin].
  ///
  /// Use the [of] constructor to wrap a function directly.
  ActorGroup(Handler<M, A> handler,
      {int size = 6, GroupStrategy<M, A>? strategy})
      : size = size,
        _group =
            _Group(_buildActors(size, handler), strategy ?? RoundRobin<M, A>());

  /// Creates an [ActorGroup] with the given [size], based on a handler function.
  ///
  /// A [GroupStrategy] may be provided, defaulting to [RoundRobin].
  ActorGroup.of(HandlerFunction<M, A> handlerFunction,
      {int size = 6, GroupStrategy<M, A>? strategy})
      : this(asHandler(handlerFunction), size: size, strategy: strategy);

  static List<Messenger<M, A>> _buildActors<M extends Object, A extends Object>(
      int size, Handler<M, A> handler) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be a positive number');
    }

    return List.generate(size, (_) => Actor(handler), growable: false);
  }

  @override
  FutureOr<A> send(M message) {
    return _group.handle(message);
  }

  @override
  FutureOr<void> close() {
    return _group.close();
  }
}
