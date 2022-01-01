# Actors example: word count

This example is a tiny Dart application that counts words in the given files. If directories are given, then the
word count on all files within the directory and its children, recursively, are counted.

The actual computations may be made on the main `Isolate` or on one or more `Actor`s.

The first argument may be one of:

* `local` - use a `LocalMessenger` (i.e. run computation in the main `Isolate`).
* `actor` - start a single `Actor`.
* `group` - start an `ActorGroup` with `numberOfProcessors` actors in it.

Example usage:

```
dart bin/word_count.dart local ../lib
```

You can also pre-compile the Dart script into a binary so it will run a lot faster:

```
# compile
dart compile exe bin/word_count.dart

# run
bin/word_count.exe local ../lib
```

On a large enough input, it should become clear that `group` can run much faster as it is able to leverage all
CPU cores available instead of only one (though Dart may use many cores for IO even when running all code on a single
`Isolate`).
