import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dext/dext.dart';

import 'config.dart';
import 'download_task.dart';
import 'entities.dart';
import 'http.dart';
import 'logger.dart';
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
    ..addOption('url', abbr: 'u', help: 'm3u8 url')
    ..addOption('output', abbr: 'o', help: 'output file name (not have ext)')
    ..addOption(
      'protocol',
      abbr: 'p',
      defaultsTo: 'file,crypto,data,http,tcp,https,tls',
      help: 'supported protocol (for ffmpeg merge)',
    )
    ..addOption('ext', help: 'output file ext.', defaultsTo: 'mp4')
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

  Future<void> downloadM3u8(
    M3u8 m3u8,
    String outputPath,
    String outputMediaPath,
  ) async {
    final manager = DownloadManager();
    for (var i = 0; i < m3u8.tsList.length; i++) {
      final ts = m3u8.tsList[i];

      final uri = ts.wholeUri;
      final tmpName = '$outputPath/$i.ts';

      manager.addTask(DownloadTask(uri, tmpName));
    }

    await manager.start();
  }

  Future<void> mergeTs(
    M3u8 m3u8,
    String outputPath,
    String outputMediaPath,
  ) async {
    final m3u8FilePath = '$outputPath/index.m3u8';

    final m3u8Buffer = StringBuffer();

    // write header
    m3u8Buffer.writeln('#EXTM3U');
    m3u8Buffer.writeln('#EXT-X-VERSION:3');
    m3u8Buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');

    // write key
    final key = m3u8.key;
    if (key != null) {
      m3u8Buffer.writeln(key.resolveMetaText());
    }

    // write ts
    for (var i = 0; i < m3u8.tsList.length; i++) {
      final ts = m3u8.tsList[i];
      final tsName = '$i.ts';
      m3u8Buffer.writeln(ts.metaText);
      m3u8Buffer.writeln(tsName);
    }

    // write end
    m3u8Buffer.writeln('#EXT-X-ENDLIST');

    // write m3u8 file
    final m3u8File = File(m3u8FilePath);
    await m3u8File.create(recursive: true);
    await m3u8File.writeAsString(m3u8Buffer.toString());

    String ffmpegCmd =
        'ffmpeg -protocol_whitelist "${Config.supportedProtocol}" -i $m3u8FilePath -c copy $outputMediaPath';

    // run cmd
    final result = await Process.start('sh', ['-c', ffmpegCmd]);

    result.stdout.transform(utf8.decoder).listen((event) {
      logger.log(event);
    });

    final totalTsLength = m3u8.tsList.length;

    var time = 0;
    void showMergeProgress(String event) {
      time++;

      if (time % 20 != 0) {
        return;
      }

      // Example: Opening 'crypto:download/1.ts' for reading
      final regex = RegExp('Opening \'(.*)\' for reading');
      final match = regex.firstMatch(event);
      if (match != null) {
        final nameInfo = match.group(1)!;

        if (!nameInfo.endsWith('.ts')) {
          return;
        }

        final tsName = nameInfo.split('/').last;
        final noExtName = tsName.split('.').first;

        final index = noExtName.toInt();
        final mergeProgress = index / totalTsLength;
        final progressText = (mergeProgress * 100).toStringAsFixed(2);
        logger.log('Merge progress: $progressText%');
      }
    }

    result.stderr.transform(utf8.decoder).listen((event) {
      logger.verbose(event);
      showMergeProgress(event);
    });

    final exitCode = await result.exitCode;
    logger.log('exitCode: $exitCode');

    if (exitCode == 0) {
      logger.log('Merge success');

      if (Config.removeTemp) {
        final dir = Directory(outputPath);
        await dir.delete(recursive: true);
        logger.log('Remove temp path: $outputPath');
      }

      logger.log('Output: $outputMediaPath');
    } else {
      logger.log('Merge failed');
    }
  }

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
    final ffmpegResult = await Process.start('bash', ['-c', 'ffmpeg -version']);
    if (await ffmpegResult.exitCode != 0) {
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
