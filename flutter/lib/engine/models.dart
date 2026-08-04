// Domain models + JSON mapping for the engine protocol (docs/engine-protocol.md).
//
// These mirror the Python core entities in app/core/entities.py. Field names
// and enum string values must stay byte-for-byte identical to what
// app/engine/engine_cli.py emits so the wire contract stays stable.

import 'dart:io';

/// Supported file kinds.
enum FileKind { pdf, image, unsupported }

/// Per-file compression outcome.
enum JobStatus { pending, running, done, failed, skipped }

/// Preset compression levels (map to concrete options by the engine).
enum CompressionLevel { high, balanced, maximum }

/// How/where compressed output is written.
enum OutputMode { suffix, directory, overwrite }

/// Accepted file extensions, matching app/core/entities.py.
const Set<String> pdfExtensions = {'.pdf'};
const Set<String> imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.bmp',
  '.tif',
  '.tiff',
  '.gif',
};

String _suffixOf(String path) {
  final base = path.toLowerCase();
  final dot = base.lastIndexOf('.');
  if (dot < 0 || dot == base.length - 1) return '';
  return base.substring(dot);
}

/// Infers [FileKind] from a file path's extension.
FileKind detectKind(String path) {
  final s = _suffixOf(path);
  if (pdfExtensions.contains(s)) return FileKind.pdf;
  if (imageExtensions.contains(s)) return FileKind.image;
  return FileKind.unsupported;
}

/// One file in the compression queue, mirroring `entities.FileItem`.
class FileItem {
  const FileItem({
    required this.path,
    required this.kind,
    required this.size,
    required this.name,
    required this.parentDir,
  });

  final String path;
  final FileKind kind;
  final int size;
  final String name;
  final String parentDir;

  factory FileItem.fromPath(String path) {
    final f = File(path);
    int size = 0;
    try {
      size = f.existsSync() ? f.lengthSync() : 0;
    } on FileSystemException {
      size = 0;
    }
    final lastSep = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = lastSep == -1 ? path : path.substring(lastSep + 1);
    final parent = lastSep == -1 ? '' : path.substring(0, lastSep);
    return FileItem(
      path: path,
      kind: detectKind(path),
      size: size,
      name: name,
      parentDir: parent,
    );
  }
}

/// PDF compression options, mirroring `entities.PdfOptions`.
class PdfOptions {
  const PdfOptions({
    this.imageQuality = 70,
    this.maxImageDpi = 144,
    this.removeMetadata = true,
    this.deflate = true,
    this.garbage = 4,
  });

  final int imageQuality;
  final int maxImageDpi;
  final bool removeMetadata;
  final bool deflate;
  final int garbage;

  Map<String, dynamic> toJson() => {
    'image_quality': imageQuality,
    'max_image_dpi': maxImageDpi,
    'remove_metadata': removeMetadata,
    'deflate': deflate,
    'garbage': garbage,
  };
}

/// Image compression options, mirroring `entities.ImageOptions`.
class ImageOptions {
  const ImageOptions({
    this.quality = 72,
    this.resizeMax = 0,
    this.preserveFormat = true,
    this.stripMetadata = true,
  });

  final int quality;
  final int resizeMax;
  final bool preserveFormat;
  final bool stripMetadata;

  Map<String, dynamic> toJson() => {
    'quality': quality,
    'resize_max': resizeMax,
    'preserve_format': preserveFormat,
    'strip_metadata': stripMetadata,
  };
}

/// Level presets (same numbers as `entities._LEVEL_PRESETS`).
class LevelPreset {
  const LevelPreset({
    required this.label,
    required this.description,
    required this.pdf,
    required this.image,
  });

  final String label;
  final String description;
  final PdfOptions pdf;
  final ImageOptions image;
}

const Map<CompressionLevel, LevelPreset> levelPresets = {
  CompressionLevel.high: LevelPreset(
    label: 'High',
    description: 'Best quality, modest savings',
    pdf: PdfOptions(imageQuality: 85, maxImageDpi: 180),
    image: ImageOptions(quality: 82),
  ),
  CompressionLevel.balanced: LevelPreset(
    label: 'Balanced',
    description: 'Great quality, good savings',
    pdf: PdfOptions(imageQuality: 70, maxImageDpi: 144),
    image: ImageOptions(quality: 72),
  ),
  CompressionLevel.maximum: LevelPreset(
    label: 'Maximum',
    description: 'Smallest size, some quality loss',
    pdf: PdfOptions(imageQuality: 50, maxImageDpi: 100),
    image: ImageOptions(quality: 50),
  ),
};

/// Full user-facing compression settings, mirroring `entities.CompressionOptions`.
class CompressionOptions {
  const CompressionOptions({
    this.level = CompressionLevel.balanced,
    this.outputMode = OutputMode.suffix,
    this.outputDir = '',
    this.suffix = '_compressed',
    this.maxSizeMb,
    this.pdf,
    this.image,
  });

  final CompressionLevel level;
  final OutputMode outputMode;
  final String outputDir;
  final String suffix;
  final double? maxSizeMb;
  final PdfOptions? pdf;
  final ImageOptions? image;

  /// Byte budget for the max-size target, or null when unset.
  int? get targetBytes => (maxSizeMb == null || maxSizeMb! <= 0)
      ? null
      : (maxSizeMb! * 1024 * 1024).round();

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'output_mode': outputMode.name,
    'output_dir': outputDir,
    'suffix': suffix,
    'max_size_mb': maxSizeMb,
    'pdf': pdf?.toJson(),
    'image': image?.toJson(),
  };
}

/// Outcome of compressing one file, mirroring `entities.JobResult`.
class JobResult {
  const JobResult({
    required this.path,
    required this.name,
    required this.kind,
    required this.status,
    required this.outputPath,
    required this.originalSize,
    required this.compressedSize,
    this.error = '',
  });

  final String path;
  final String name;
  final FileKind kind;
  final JobStatus status;
  final String outputPath;
  final int originalSize;
  final int compressedSize;
  final String error;

  double get savingsPercent {
    if (originalSize <= 0) return 0;
    final saved = (originalSize - compressedSize).clamp(0, originalSize);
    return (saved / originalSize * 100 * 10).round() / 10;
  }

  int get savings => (originalSize - compressedSize).clamp(0, originalSize);

  factory JobResult.fromJson(Map<String, dynamic> json) {
    return JobResult(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: _kindFrom(json['kind'] as String? ?? ''),
      status: _statusFrom(json['status'] as String? ?? 'pending'),
      outputPath: json['output_path'] as String? ?? '',
      originalSize: (json['original_size'] as num?)?.toInt() ?? 0,
      compressedSize: (json['compressed_size'] as num?)?.toInt() ?? 0,
      error: json['error'] as String? ?? '',
    );
  }
}

/// Persisted application settings, mirroring `entities.AppSettings`.
class AppSettings {
  const AppSettings({
    this.theme = 'dark',
    this.accentColor = '#3b82f6',
    this.historyLimit = 200,
    this.defaultLevel = 'balanced',
    this.outputMode = 'suffix',
    this.outputDir = '',
    this.overwriteConfirmation = true,
    this.addToHistory = true,
  });

  final String theme;
  final String accentColor;
  final int historyLimit;
  final String defaultLevel;
  final String outputMode;
  final String outputDir;
  final bool overwriteConfirmation;
  final bool addToHistory;

  CompressionLevel get defaultCompressionLevel =>
      _levelFrom(defaultLevel) ?? CompressionLevel.balanced;

  OutputMode get defaultOutputMode =>
      _modeFrom(outputMode) ?? OutputMode.suffix;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    theme: json['theme'] as String? ?? 'dark',
    accentColor: json['accent_color'] as String? ?? '#3b82f6',
    historyLimit: (json['history_limit'] as num?)?.toInt() ?? 200,
    defaultLevel: json['default_level'] as String? ?? 'balanced',
    outputMode: json['output_mode'] as String? ?? 'suffix',
    outputDir: json['output_dir'] as String? ?? '',
    overwriteConfirmation: json['overwrite_confirmation'] as bool? ?? true,
    addToHistory: json['add_to_history'] as bool? ?? true,
  );
}

// ------------------------------------------------------------- enum mapping --

CompressionLevel? _levelFrom(String v) {
  for (final l in CompressionLevel.values) {
    if (l.name == v) return l;
  }
  return null;
}

OutputMode? _modeFrom(String v) {
  for (final m in OutputMode.values) {
    if (m.name == v) return m;
  }
  return null;
}

FileKind _kindFrom(String v) {
  for (final k in FileKind.values) {
    if (k.name == v) return k;
  }
  return FileKind.unsupported;
}

JobStatus _statusFrom(String v) {
  for (final s in JobStatus.values) {
    if (s.name == v) return s;
  }
  return JobStatus.pending;
}
