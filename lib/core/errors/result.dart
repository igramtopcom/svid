import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

/// A Result type for handling success and failure cases
@freezed
class Result<T> with _$Result<T> {
  const factory Result.success(T data) = Success<T>;
  const factory Result.failure(Exception exception) = Failure<T>;
}

/// Extension methods for Result
extension ResultX<T> on Result<T> {
  /// Check if the result is a success
  bool get isSuccess => this is Success<T>;

  /// Check if the result is a failure
  bool get isFailure => this is Failure<T>;

  /// Get the data if success, otherwise return null
  T? get dataOrNull => when(
        success: (data) => data,
        failure: (_) => null,
      );

  /// Get the exception if failure, otherwise return null
  Exception? get exceptionOrNull => when(
        success: (_) => null,
        failure: (exception) => exception,
      );

  /// Get the data if success, otherwise throw the exception
  T get dataOrThrow => when(
        success: (data) => data,
        failure: (exception) => throw exception,
      );

  // Note: map() and flatMap() were removed because Freezed generates
  // instance methods with the same names that shadow extensions.
  // Use fold() or when() instead for transformations.

  /// Handle both success and failure cases
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(Exception exception) onFailure,
  }) =>
      when(
        success: onSuccess,
        failure: onFailure,
      );

  /// Execute a function on success
  Result<T> onSuccess(void Function(T data) action) {
    if (this is Success<T>) {
      action((this as Success<T>).data);
    }
    return this;
  }

  /// Execute a function on failure
  Result<T> onFailure(void Function(Exception exception) action) {
    if (this is Failure<T>) {
      action((this as Failure<T>).exception);
    }
    return this;
  }
}

/// Helper function to execute a function and wrap the result
Future<Result<T>> runCatching<T>(Future<T> Function() block) async {
  try {
    final result = await block();
    return Result.success(result);
  } on Exception catch (e) {
    return Result.failure(e);
  } catch (e) {
    return Result.failure(Exception(e.toString()));
  }
}

/// Synchronous version of runCatching
Result<T> runCatchingSync<T>(T Function() block) {
  try {
    final result = block();
    return Result.success(result);
  } on Exception catch (e) {
    return Result.failure(e);
  } catch (e) {
    return Result.failure(Exception(e.toString()));
  }
}
