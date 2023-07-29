import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:m3u8_download/src/shell.dart';

import 'config.dart';
import 'entities.dart';
import 'http.dart';
import 'logger.dart';
import 'merger.dart';
import 'stopwatch.dart';

class M3u8CommandRunner extends CommandRunner<void> {
  String getNotRepeatPath(String outputPath) {
    final realPath = '$outputPath.mp4';

    final file = File(realPath);

    if (!file.existsSync()) {
      return outputPath;
    }

    var index = 2;
    while (true) {
      final newOutputPath = '$outputPath-$index';
      final dir = '$newOutputPath.mp4';
      final file = File(dir);
      if (file.existsSync()) {
        index++;
      } else {
        return newOutputPath;
      }
    }
  }

  @override
  ArgParser argParser = ArgParser()
    ..addOption(
      'url',
      abbr: 'u',
      help: 'm3u8 url',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'output file name (not have ext)',
      defaultsTo: 'download/video',
    )
    ..addOption(
      'protocol',
      abbr: 'p',
      defaultsTo: 'file,crypto,data,http,tcp,https,tls',
      help: 'supported protocol (for ffmpeg merge)',
    )
    ..addOption(
      'ext',
      abbr: 'e',
      help: 'output file ext.',
      defaultsTo: 'mp4',
    )
    ..addOption(
      'threads',
      abbr: 't',
      defaultsTo: '20',
      help: 'download threads',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      help: 'show verbose log',
    )
    ..addFlag(
      'remove-temp',
      abbr: 'r',
      defaultsTo: true,
      help: 'remove temp file after merge',
    );

  M3u8CommandRunner(String executableName, String description)
      : super(executableName, description);

  @override
  String get usage => '${super.usage}\n\n'
      'Example: m3u8 -u http://example.com/index.m3u8 -o download';

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    final stopwatch = Stopwatch();
    stopwatch.start();
    final result = topLevelResults;

    if (result['help'] as bool) {
      logger.log(usage);
      return;
    }

    Config.verbose = result['verbose'] as bool;

    final url = result['url'] as String?;
    var outputPath = result['output'] as String?;

    if (url == null) {
      logger.log('url is null, exit');
      return;
    }

    if (!url.startsWith('http')) {
      logger.log('url is not start with http, exit');
      return;
    }

    Config.threads = int.parse(result['threads'] as String);

    final protocol = result['protocol'] as String?;
    if (protocol != null) {
      Config.supportedProtocol = protocol;
    }

    // check ffmpeg installed
    final ffmpegResult = await isProgramInstalled('ffmpeg');
    if (!ffmpegResult) {
      logger.log('ffmpeg not installed, exit');
      return;
    }

    final ext = result['ext'] as String? ?? 'mp4';

    Config.removeTemp = result['remove-temp'] as bool;

    outputPath ??= 'download';

    outputPath = outputPath.replaceAll(' ', '-');
    outputPath = getNotRepeatPath(outputPath);

    final outputMediaPath = '$outputPath.$ext';

    logger.log('Prepared to download: $url');
    logger.log('Output outputMediaFile: $outputMediaPath');
    logger.log('Output temp path: $outputPath');

    final m3u8 = await M3u8.from(url);

    // print('m3u8: $m3u8');
    logger.log('total ts count: ${m3u8.tsList.length}');
    if (m3u8.key != null) {
      logger.verbose('key: ${m3u8.key}');
    }

    stopwatch.stop();
    runtimeOverwatch.prepare = stopwatch.elapsedMilliseconds;
    stopwatch.reset();
    stopwatch.start();

    await downloadM3u8(m3u8, outputPath, outputMediaPath);
    stopwatch.stop();
    runtimeOverwatch.download = stopwatch.elapsedMilliseconds;
    stopwatch.reset();
    stopwatch.start();
    await mergeTs(m3u8, outputPath, outputMediaPath);
    runtimeOverwatch.merge = stopwatch.elapsedMilliseconds;
    stopwatch.stop();

    httpClient.close();
  }
}
