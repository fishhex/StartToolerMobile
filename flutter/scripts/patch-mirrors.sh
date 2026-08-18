#!/usr/bin/env bash
# 在 flutter create . 之后执行，把 Gradle/Maven 镜像切到国内源。
# 用法：cd flutter && bash scripts/patch-mirrors.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_DIR/android"

if [[ ! -d "$ANDROID_DIR" ]]; then
  echo "[error] $ANDROID_DIR 不存在。请先在 flutter/ 目录下执行 flutter create . --platforms=android" >&2
  exit 1
fi

WRAPPER="$ANDROID_DIR/gradle/wrapper/gradle-wrapper.properties"
BUILD="$ANDROID_DIR/build.gradle.kts"
SETTINGS="$ANDROID_DIR/settings.gradle.kts"

# 1. Gradle 分发包镜像
if [[ -f "$WRAPPER" ]]; then
  if grep -q "services.gradle.org" "$WRAPPER"; then
    sed -i '' 's|distributionUrl=https://services.gradle.org/distributions/gradle-.*-all.zip|distributionUrl=https://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-all.zip|' "$WRAPPER"
    echo "[ok] patched $WRAPPER"
  fi
fi

# 2. 项目仓库镜像（build.gradle.kts）
if [[ -f "$BUILD" ]]; then
  if ! grep -q "maven.aliyun.com" "$BUILD"; then
    sed -i '' '/^allprojects {/a\
    repositories {\
        maven { url = uri("https://maven.aliyun.com/repository/public") }\
        maven { url = uri("https://maven.aliyun.com/repository/google") }\
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }\
        google()\
        mavenCentral()\
    }\
    _INSERT_MARKER_' "$BUILD"
    # 上面的 a 命令会在 allprojects { 后插入一个重复的 repositories 块，需要清掉原始的
    # 简化做法：直接重写文件
    cat > "$BUILD" <<'KOTLIN'
allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
KOTLIN
    echo "[ok] rewrote $BUILD with mirrors"
  fi
fi

# 3. 插件管理镜像（settings.gradle.kts）
if [[ -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<'KOTLIN'
pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
KOTLIN
    echo "[ok] rewrote $SETTINGS with mirrors"
fi

echo "[done] 镜像配置已应用。"
