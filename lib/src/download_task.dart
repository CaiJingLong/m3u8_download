import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart';

import 'config.dart';
import 'http.dart';
import 'logger.dart';

class DownloadTask {
  final Uri uri;
  final String outputPath;

  const DownloadTask(this.uri, this.outputPath);
}

typedef VoidCallback = void Function();

class DownloadManager {
  final List<DownloadTask> _tasks = [];

  void addTask(DownloadTask task) {
    _tasks.add(task);
  }

  var runningCount = 0;

  var totalCount = 0;

  var finishTask = 0;

  var totalDownloadedBytes = 0;
  final stopwatch = Stopwatch();

  Future<void> start() async {
    stopwatch.start();
    final Completer<void> result = Completer();
    totalCount = _tasks.length;
    Timer.periodic(Duration(milliseconds: 50), (timer) {
      download(() {
        timer.cancel();
        result.complete();
      });
    });

    return result.future;
  }

  Future<void> download([VoidCallback? onDownloadFinish]) async {
    if (finishTask == totalCount) {
      onDownloadFinish?.call();
      return;
    }
    if (_tasks.isNotEmpty) {
      while (runningCount < Config.threads) {
        runningCount++;
        if (_tasks.isEmpty) {
          break;
        }
        final task = _tasks.removeAt(0);
        downloadFile(task);
      }
    }
  }

  double _getDownloadSpeed() {
    return totalDownloadedBytes / stopwatch.elapsed.inMilliseconds * 1000;
  }

  String formatSpeed() {
    var downloadSpeed = _getDownloadSpeed();

    final unit = ['bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];

    var index = 0;

    while (downloadSpeed > 1024) {
      downloadSpeed /= 1024;
      index++;
    }
    final unitText = unit[index];
    return '${downloadSpeed.toStringAsFixed(2)} $unitText/s';
  }

  int _guessTotalBytes() {
    // guest current download speed

    // 1. avg file size
    final avgFileSize = totalDownloadedBytes ~/ finishTask;

    // 2. guest total bytes
    return avgFileSize * totalCount;
  }

  Future<void> downloadFile(DownloadTask task) async {
    final downloadBytes = await _download(task);
    if (downloadBytes == -1) {
      throw Exception('Download failed: ${task.uri}, exit.');
    }

    _tasks.remove(task);
    runningCount--;
    finishTask++;

    final progress = finishTask / totalCount;
    final progressText = (progress * 100).toStringAsFixed(2);
    final downloadSpeedText = formatSpeed();

    var remainingTimeMilliseconds = 0.0;
    totalDownloadedBytes += downloadBytes;
    final guestTotalBytes = _guessTotalBytes();
    if (guestTotalBytes > 0) {
      final remainingBytes = guestTotalBytes - totalDownloadedBytes;
      // guest remaining time
      final downloadSpeed = _getDownloadSpeed();
      remainingTimeMilliseconds = remainingBytes / downloadSpeed;
    }

    logger.write('\rDownload progress: $progressText%, $downloadSpeedText, '
        'remaining time: ${remainingTimeMilliseconds.toStringAsFixed(2)}');
  }

  Future<int> _download(DownloadTask task) {
    if (Config.useIsolate) {
      return Isolate.run(() => _downloadFile(task));
    } else {
      return _downloadFile(task);
    }
  }

  Future<int> _downloadFile(DownloadTask task) async {
    final uri = task.uri;
    final outputPath = task.outputPath;
    final tmpOutputPath = '$outputPath.tmp';
    final tsFilePath = File(outputPath);

    final tmpFile = File(tmpOutputPath);
    if (tsFilePath.existsSync()) {
      logger.log('Skip download: $uri');
      return tsFilePath.lengthSync();
    }

    var retryCount = 0;
    while (retryCount < Config.retryCount) {
      try {
        final request = Request('GET', uri);
        final response = await httpClient.send(request);

        if (response.statusCode != 200) {
          logger.error(
            'Download failed: $uri, status code: ${response.statusCode}',
          );
          final headers = response.headers.entries
              .map((e) => "${e.key}: ${e.value}")
              .join('\n');
          logger.error(
            'Response headers: $headers',
          );
          logger.error(
            'Response body: ${await response.stream.bytesToString()}',
          );
          return -1;
        }

        await tmpFile.create(recursive: true);
        final sink = tmpFile.openWrite();
        final bytes = await response.stream.toBytes();
        sink.add(bytes);
        await sink.flush();
        await sink.close();

        if (tmpFile.existsSync()) {
          tmpFile.renameSync(outputPath);
        }

        return bytes.length;
      } catch (e) {
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
        logger.log('Download failed: $uri, retry: $retryCount');
        retryCount++;
      }
    }

    throw Exception('Download failed: $uri');
  }
}
