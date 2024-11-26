import 'dart:convert';
import 'dart:io';

import 'package:dext/dext.dart';

import 'config.dart';
import 'download_task.dart';
import 'entities.dart';
import 'logger.dart';
import 'util/string_util.dart';

Future<void> mergeTs(
  M3u8 m3u8,
  String outputPath,
  String outputMediaPath,
) async {
  final m3u8FilePath = '$outputPath/index.m3u8';

  final content = await m3u8.getLocalM3u8Content(m3u8, outputPath);

  // write m3u8 file
  final m3u8File = File(m3u8FilePath);
  await m3u8File.create(recursive: true);
  await m3u8File.writeAsString(content);

  if (!m3u8File.existsSync()) {
    throw Exception('Create m3u8 file failed, download stop.');
  }

  String ffmpegCmd =
      'ffmpeg -allowed_extensions ALL -protocol_whitelist ${Config.supportedProtocol} -i $m3u8FilePath -c copy $outputMediaPath';

  logger.log('\n');
  logger.log('Start merge ts files');
  logger.log('ffmpegCmd: $ffmpegCmd');

  // run cmd
  Process result;

  if (Platform.isLinux || Platform.isMacOS) {
    result = await Process.start('sh', ['-c', ffmpegCmd]);
  } else if (Platform.isWindows) {
    final cmd = 'ffmpeg';
    final args = ffmpegCmd.split(' ').sublist(1);
    result = await Process.start(cmd, args);
  } else {
    throw Exception(
        'Unsupported platform, just support Linux, MacOS and Windows');
  }

  result.stdout.transform(utf8.decoder).listen((event) {
    logger.log(event);
  });

  final totalTsLength = m3u8.tsList.length;

  void showMergeProgress(String event) {
    // Example: Opening 'crypto:download/1.ts' for reading
    final regex = RegExp('Opening \'(.*)\' for reading');
    final match = regex.firstMatch(event);
    if (match != null) {
      final nameInfo = match.group(1)!;

      if (!nameInfo.endsWith(m3u8.ext)) {
        return;
      }

      final tsName = nameInfo.split('/').last;
      final noExtName = tsName.split('.').first;

      final index = noExtName.toInt();
      final mergeProgress = index / totalTsLength;
      final progressText = (mergeProgress * 100).toStringAsFixed(2);
      logger.write('\rMerge progress: $progressText%');
    }
  }

  result.stderr.transform(utf8.decoder).listen((event) {
    logger.verbose(event);
    try {
      showMergeProgress(event);
      // ignore: empty_catches, unused_catch_clause
    } on Exception catch (e) {}
  });

  final exitCode = await result.exitCode;
  logger.write('\n');
  logger.log('exitCode: $exitCode');

  if (exitCode == 0) {
    logger.log('Merge success');

    if (Config.removeTemp) {
      final dir = Directory(outputPath);
      await dir.delete(recursive: true);
      logger.log('Remove temp path: $outputPath');
    }

    final fileSize = File(outputMediaPath).lengthSync();

    final sizeText = StringUtils.formatSize(fileSize);

    logger.log('Output: $outputMediaPath ($sizeText)');
  } else {
    logger.log('Merge failed');
  }
}

Future<void> downloadM3u8(
  M3u8 m3u8,
  String outputPath,
  String outputMediaPath,
) async {
  final manager = DownloadManager();
  for (var i = 0; i < m3u8.tsList.length; i++) {
    final ts = m3u8.tsList[i];

    final uri = ts.wholeUri;
    final outputTsPath = '$outputPath/$i${m3u8.ext}';
    ts.outputPath = outputTsPath;

    manager.addTask(DownloadTask(uri, outputTsPath));
  }

  await manager.start();
}

Future<void> downloadKey(
  M3u8 m3u8,
  String outputPath,
) async {
  final key = m3u8.key;
  if (key != null) {
    await key.download(outputPath);
  }
}
