import 'package:m3u8_download/src/shell.dart';

Future<void> main() async {
  await isProgramInstalled('ffmpeg').then((value) => print(value));
  await isProgramInstalled('dart').then((value) => print(value));
  await isProgramInstalled('powershell').then((value) => print(value));
  await isProgramInstalled('flutter').then((value) => print(value));
}
