import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class CompressionProfile {
  const CompressionProfile({
    required this.width,
    required this.frameStep,
    required this.numColors,
  });

  final int width;
  final int frameStep;
  final int numColors;
}

const _defaultProfile = CompressionProfile(
  width: 360,
  frameStep: 2,
  numColors: 48,
);

const _profiles = <String, CompressionProfile>{
  'steps.gif': CompressionProfile(width: 320, frameStep: 3, numColors: 40),
  'meditate.gif': CompressionProfile(width: 320, frameStep: 3, numColors: 40),
  'fasting.gif': CompressionProfile(width: 320, frameStep: 3, numColors: 40),
  'calorie.gif': CompressionProfile(width: 320, frameStep: 3, numColors: 40),
  'sleep.gif': CompressionProfile(width: 320, frameStep: 3, numColors: 40),
  'happy.gif': CompressionProfile(width: 360, frameStep: 2, numColors: 48),
  'rain.gif': CompressionProfile(width: 360, frameStep: 2, numColors: 48),
  'angry.gif': CompressionProfile(width: 360, frameStep: 2, numColors: 48),
  'neutral.gif': CompressionProfile(width: 360, frameStep: 2, numColors: 48),
};

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help')) {
    _printUsage();
    exit(args.contains('--help') ? 0 : 64);
  }

  String? outputDir;
  final inputPaths = <String>[];

  for (final arg in args) {
    if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
      continue;
    }
    inputPaths.add(arg);
  }

  if (inputPaths.isEmpty) {
    _printUsage();
    exit(64);
  }

  final outDirectory = outputDir == null ? null : Directory(outputDir);
  outDirectory?.createSync(recursive: true);

  for (final inputPath in inputPaths) {
    _compressGif(inputPath, outDirectory: outDirectory);
  }
}

void _compressGif(String inputPath, {Directory? outDirectory}) {
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Missing file: $inputPath');
    exitCode = 1;
    return;
  }

  final fileName = inputFile.uri.pathSegments.last;
  final profile = _profiles[fileName] ?? _defaultProfile;
  final originalBytes = inputFile.readAsBytesSync();
  final decoder = img.GifDecoder();
  final animation = decoder.decode(originalBytes);

  if (animation == null) {
    stderr.writeln('Failed to decode GIF: $inputPath');
    exitCode = 1;
    return;
  }

  final resized = img.copyResize(
    animation,
    width: profile.width,
    interpolation: img.Interpolation.average,
  );

  final sampled = _sampleFrames(resized, frameStep: profile.frameStep);
  sampled.loopCount = animation.loopCount;

  final encoder = img.GifEncoder(
    numColors: profile.numColors,
    quantizerType: img.QuantizerType.octree,
    dither: img.DitherKernel.none,
  );
  final encodedBytes = encoder.encode(sampled);

  final outputPath = outDirectory == null
      ? inputPath
      : '${outDirectory.path}${Platform.pathSeparator}$fileName';
  final outputFile = File(outputPath);

  if (outDirectory == null && encodedBytes.length >= originalBytes.length) {
    stdout.writeln(
      'Skipped $fileName because compressed output was not smaller '
      '(${_formatBytes(encodedBytes.length)} >= ${_formatBytes(originalBytes.length)}).',
    );
    return;
  }

  final tempPath = '$outputPath.tmp';
  File(tempPath).writeAsBytesSync(encodedBytes, flush: true);
  File(tempPath).renameSync(outputPath);

  stdout.writeln(
    '$fileName: ${animation.width}x${animation.height}, '
    '${animation.numFrames} frames -> ${sampled.width}x${sampled.height}, '
    '${sampled.numFrames} frames, '
    '${_formatBytes(originalBytes.length)} -> ${_formatBytes(encodedBytes.length)}',
  );
}

img.Image _sampleFrames(img.Image animation, {required int frameStep}) {
  final normalizedStep = math.max(frameStep, 1);
  img.Image? firstFrame;

  for (var index = 0; index < animation.numFrames; index += normalizedStep) {
    final endExclusive = math.min(index + normalizedStep, animation.numFrames);
    var durationMs = 0;
    for (var frameIndex = index; frameIndex < endExclusive; frameIndex++) {
      durationMs += math.max(animation.frames[frameIndex].frameDuration, 40);
    }

    final sourceFrame = animation.frames[index];
    final frame = img.Image.from(sourceFrame, noAnimation: true)
      ..frameDuration = durationMs;

    if (firstFrame == null) {
      firstFrame = frame;
      continue;
    }

    firstFrame.addFrame(frame);
  }

  if (firstFrame == null) {
    throw StateError('Animation did not contain any frames.');
  }

  return firstFrame;
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(value >= 10 || unitIndex == 0 ? 0 : 1)}${units[unitIndex]}';
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/compress_gifs.dart [--output-dir=/path] <gif> [<gif> ...]',
  );
}
