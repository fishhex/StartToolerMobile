// lib/core/app_state.dart

enum AppStage { splash, disconnected, tokenRequired, connected }

class AppState {
  AppState._();

  static AppStage stage = AppStage.splash;
}