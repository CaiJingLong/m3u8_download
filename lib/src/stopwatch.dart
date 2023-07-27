import 'logger.dart';

class RuntimeStopwatch {
  int? total;
  int? prepare;
  int? download;
  int? merge;
  int? clean;

  void _showTime(String tag, int? time) {
    if (time != null) {
      final duration = Duration(milliseconds: time);
      logger.log('The $tag time: $duration');
    }
  }

  void logTime() {
    logger.log('\nThe runtime:');
    _showTime('prepare', prepare);
    _showTime('download', download);
    _showTime('merge', merge);
    _showTime('clean', clean);
    _showTime('total', total);
  }
}

final runtimeOverwatch = RuntimeStopwatch();
