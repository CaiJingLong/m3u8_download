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

  var guestTotalBytes = -1;

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

  String formatSpeed() {
    var downloadSpeed =
        totalDownloadedBytes / stopwatch.elapsed.inMilliseconds * 1000;

    final unit = ['bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];

    var index = 0;

    while (downloadSpeed > 1024) {
      downloadSpeed /= 1024;
      index++;
    }
    final unitText = unit[index];
    return '${downloadSpeed.toStringAsFixed(2)} $unitText/s';
  }

  Future<void> downloadFile(DownloadTask task) async {
    final downloadBytes = await _download(task);

    if (guestTotalBytes == -1) {
      guestTotalBytes = downloadBytes * totalCount;
    }

    totalDownloadedBytes += downloadBytes;

    _tasks.remove(task);
    runningCount--;
    finishTask++;

    final progress = finishTask / totalCount;
    final progressText = (progress * 100).toStringAsFixed(2);
    final downloadSpeedText = formatSpeed();

    var remainingTimeSeconds = 0;
    if (guestTotalBytes > 0) {
      final remainingBytes = guestTotalBytes - totalDownloadedBytes;
      remainingTimeSeconds =
          (remainingBytes / totalDownloadedBytes * stopwatch.elapsed.inSeconds)
              .toInt();
    }

    logger.write('\rDownload progress: $progressText%, $downloadSpeedText, '
        'remaining time: $remainingTimeSeconds seconds');
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
      return 0;
    }

    var retryCount = 0;
    while (retryCount < Config.retryCount) {
      try {
        final request = Request('GET', uri);
        final response = await httpClient.send(request);

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
