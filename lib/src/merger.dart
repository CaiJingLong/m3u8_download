import 'dart:convert';
import 'dart:io';

import 'package:dext/dext.dart';

import 'config.dart';
import 'download_task.dart';
import 'entities.dart';
import 'logger.dart';

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
