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
import 'versions.dart';

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
    ..addOption(
      'retry-count',
      abbr: 'c',
      defaultsTo: '5',
      help: 'retry count of each ts file',
    )
    ..addFlag(
      'version',
      abbr: 'V',
      defaultsTo: false,
      help: 'show version',
    )
    ..addFlag(
      'isolate',
      abbr: 'i',
      defaultsTo: false,
      help: 'use isolate download',
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

    if (result['version'] as bool) {
      logger.log('version: ${Versions.version}');
      return;
    }

    Config.verbose = result['verbose'] as bool;
    Config.useIsolate = result['isolate'] as bool;
    Config.retryCount = int.parse(result['retry-count'] as String);

    final url = result['url'] as String?;
    var outputPath = (result['output'] as String?) ?? 'download';

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
    const outputNameMapping = {
      ' ': '-',
      '&': '-',
      '?': '-',
      '=': '-',
      '%': '-',
      '\$': '-',
      '@': '-',
    };
    for (final kv in outputNameMapping.entries) {
      final key = kv.key;
      final value = kv.value;
      outputPath = outputPath.replaceAll(key, value);
    }

    outputPath = getNotRepeatPath(outputPath);

    try {
      final outputMediaPath = '$outputPath.$ext';

      logger.log('Prepared to download: $url');
      logger.log('Output outputMediaFile: $outputMediaPath');
      logger.log('Output temp path: $outputPath');

      final m3u8 = await M3u8.from(url, outputPath);

      // print('m3u8: $m3u8');
      logger.log('total ts count: ${m3u8.tsList.length}');
      if (m3u8.key != null) {
        // logger.verbose('key: ${m3u8.key}');
        logger.verbose('m3u8 key: ${m3u8.key?.text}');
        logger.verbose('m3u8 key: ${m3u8.key?.resolveMetaText()}');
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
    } finally {
      //
      clear(outputPath);
    }
  }

  void clear(String outputPath) {
    final dir = Directory(outputPath);
    if (!dir.existsSync()) {
      return;
    }

    final list = dir.listSync();
    if (list.isEmpty) {
      // If the dir is empty, delete dir
      dir.deleteSync();
    }
  }
}
