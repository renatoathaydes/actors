import 'package:dartle/dartle_dart.dart';

final dartleDart = DartleDart();

void main(List<String> args) {
  run(args, tasks: {
    ...dartleDart.tasks,
  }, defaultTasks: {
    dartleDart.build
  });
}
