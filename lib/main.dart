import 'dart:io';

import 'main_desktop.dart' as desktop;
import 'main_mobile.dart' as mobile;

/// Selects mobile or desktop entry point based on the runtime platform.
/// Platform detection at bootstrap is the one sanctioned use of dart:io Platform;
/// all feature code uses appVariantProvider instead.
void main() {
  if (Platform.isIOS || Platform.isAndroid) {
    mobile.main();
  } else {
    desktop.main();
  }
}
