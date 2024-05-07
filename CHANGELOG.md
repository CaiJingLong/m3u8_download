## 1.6.6

- Fix: the m3u8 in m3u8 support http params.
- Fix: support empty line in m3u8 file.

## 1.6.5

- Change log for ffmpeg merge cmd.

## 1.6.4

- Fix remaining time calculation.

## 1.6.3

- Add remaining time to download progress log.

## 1.6.2

- Output file size will be displayed in the log when the download is complete.

## 1.6.1

- Change merge log format.
- Use tmp file before download finish.

## 1.6.0

- Add retry count for download.
- If download file error, the outputFile will be deleted.

## 1.5.1

- Update download progress log.

## 1.5.0

- Add `-i` to open `isolate` mode to download files.

## 1.4.2

- Fix version problem.

## 1.4.1

- Fix: solve the problem of multiple rows of keys in the m3u8 file.

## 1.4.0

- Add `--version` flag.

## 1.3.5

- fix: If temp dir is empty, remove it.

## 1.3.4

- fix: replace some characters that cannot be used in file names.

## 1.3.3

- fix: An error will be reported if the key in the m3u8 file does not contain a 'URI'.

## 1.3.2

- Fix bug: the executor in windows can use in cmd and powershell.

## 1.3.1

- Fix bug: remove test code in bin.
- Change default `output` to `./download/video`.
- params `ext` have abbreviation `e`.

## 1.3.0

- Support windows.

## 1.2.0

- Split a single file into multiple files.

## 1.1.1

- Fix: issue with spaces in `output`.

- Downgrade dart constraint  to `>=2.12.0 <4.0.0`.

## 1.1.0

- Change log and add verbose option.
- Display runtime after download ends.
- Add download speed.
- Display merge progress.
- Support ext name

## 1.0.0

- Initial version.
