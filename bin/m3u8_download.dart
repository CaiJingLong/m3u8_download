import 'dart:async';

import 'package:m3u8_download/src/command_runner.dart';
import 'package:m3u8_download/src/stopwatch.dart';

Future<void> main(List<String> args) async {
  // args = [
  //   '--url',
  //   'xxx/index.m3u8',
  //   '--segment-ext',
  //   'jpeg',
  // ];

  final stopwatch = Stopwatch();
  stopwatch.start();
  final runner = M3u8CommandRunner(
    'm3u8_download',
    'Download m3u8 and merge to video(mp4)',
  );

  await runner.run(args);
  stopwatch.stop();
  runtimeOverwatch.total = stopwatch.elapsedMilliseconds;
  runtimeOverwatch.logTime();
}
