import 'enums.dart';

class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.fileSource,
    required this.outputType,
    required this.outputPath,
    this.thumbnail = '',
    this.favorite = false,
  });

  final String id, name, fileSource, outputPath, thumbnail;
  final DateTime createdAt;
  final OutputType outputType;
  final bool favorite;

  ProjectItem copyWith({
    String? name,
    String? outputPath,
    bool? favorite,
    OutputType? outputType,
  }) =>
      ProjectItem(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        fileSource: fileSource,
        outputType: outputType ?? this.outputType,
        outputPath: outputPath ?? this.outputPath,
        thumbnail: thumbnail,
        favorite: favorite ?? this.favorite,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'fileSource': fileSource,
        'outputType': outputType.name,
        'outputPath': outputPath,
        'thumbnail': thumbnail,
        'favorite': favorite,
      };

  factory ProjectItem.fromMap(Map<String, dynamic> m) => ProjectItem(
        id: m['id'] as String,
        name: m['name'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        fileSource: m['fileSource'] as String,
        outputType: OutputType.values.byName(m['outputType'] as String),
        outputPath: m['outputPath'] as String,
        thumbnail: m['thumbnail'] as String? ?? '',
        favorite: m['favorite'] as bool? ?? false,
      );
}
