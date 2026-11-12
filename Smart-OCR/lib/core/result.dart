import 'failure.dart';

sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };

  /// Jalankan [body]; exception apa pun dipetakan lewat [onError].
  static Future<Result<T>> guard<T>(
    Future<T> Function() body,
    Failure Function(Object error) onError,
  ) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(onError(e));
    }
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
