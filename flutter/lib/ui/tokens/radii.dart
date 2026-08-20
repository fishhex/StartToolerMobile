// lib/ui/tokens/radii.dart
//
// 圆角 token（对齐 D06 §4.4）。

import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  static const double sm = 6;
  static const double md = 12;
  static const double lg = 20;

  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
}