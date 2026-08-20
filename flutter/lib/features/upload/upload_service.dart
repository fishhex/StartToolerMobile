// lib/features/upload/upload_service.dart

import '../../core/mock/seed_data.dart';

typedef OnUploadProgress = void Function(int current, int total);

abstract class UploadService {
  /// 上传文件；total 拍，每拍回调一次 progress(current, total)，最后一次 current == total。
  Future<void> upload({
    required String projectName,
    required List<SelectedFile> files,
    required OnUploadProgress onProgress,
  });
}

class UploadMock implements UploadService {
  UploadMock();

  @override
  Future<void> upload({
    required String projectName,
    required List<SelectedFile> files,
    required OnUploadProgress onProgress,
  }) async {
    const totalTicks = 20;
    const tickMs = 100;
    for (int i = 1; i <= totalTicks; i++) {
      await Future.delayed(const Duration(milliseconds: tickMs));
      onProgress(i, totalTicks);
    }
  }
}