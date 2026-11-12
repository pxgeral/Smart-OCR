sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

final class ScanFailure extends Failure {
  const ScanFailure(super.message);
}

final class OcrFailure extends Failure {
  const OcrFailure(super.message);
}

final class ConversionFailure extends Failure {
  const ConversionFailure(super.message);
}

final class ExportFailure extends Failure {
  const ExportFailure(super.message);
}

final class StorageFailure extends Failure {
  const StorageFailure(super.message);
}
