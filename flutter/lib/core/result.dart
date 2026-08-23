// lib/core/result.dart
//
// 极简 Result 类型 —— T1 用，T4 可升级到 fpdart / dartz（本期不引入）。

sealed class Result<T, E> {
  const Result();

  R when<R>({required R Function(T) ok, required R Function(E) err}) {
    final self = this;
    if (self is Ok<T, E>) return ok(self.value);
    if (self is Err<T, E>) return err(self.error);
    throw StateError('unreachable Result variant');
  }
}

class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;
}

class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;
}