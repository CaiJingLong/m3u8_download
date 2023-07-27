# m3u8_download

## Why have this project

I want to download some video, but use `ffmpeg -i xxx -c copy xxx.mp4` is too slow.

Because it seems that there is a limited speed for single-threaded downloads,
the overall speed is very slow, and online playback will freeze,
but multi-threaded downloads will not be very slow. So I wrote this tool,
which can parse m3u8 and download ts files in multiple threads,
and do the "merging" work locally to speed up.

## require

The executable is available for Linux and macOS.

And, you need to install [ffmpeg](https://ffmpeg.org/) first.

## Install

```sh
dart pub global activate m3u8_download
```

```sh
git clone https://github.com/CaiJingLong/m3u8_download.git
cd m3u8_download
dart pub global activate -s path .
```

Or, download from [release](https://github.com/CaiJingLong/m3u8_download/releases)

```sh
# after download
chmod +x m3u8
```

## Usage

### pub global

```sh
m3u8 -u xxx -o download
```

### use source code

```sh
dart bin/m3u8_download.dart -u xxx
```

## help for command

```sh
$ m3u8 -h
Download m3u8 and merge to mp4

Usage: m3u8_download <command> [arguments]

Global options:
-u, --url                 m3u8 url
-o, --output              output file name (not have ext)
-p, --protocol            supported protocol (for ffmpeg merge)
                          (defaults to "file,crypto,data,http,tcp,https,tls")
    --ext                 output file ext.
                          (defaults to "mp4")
-t, --threads             download threads
                          (defaults to "20")
-v, --[no-]verbose        show verbose log
-r, --[no-]remove-temp    remove temp file after merge
                          (defaults to on)
-h, --help                Print this usage information.

Available commands:
  help   Display help information for m3u8_download.

Run "m3u8_download help <command>" for more information about a command.

Example: m3u8 -u http://example.com/index.m3u8 -o download
```
