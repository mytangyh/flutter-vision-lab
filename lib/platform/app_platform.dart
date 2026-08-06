import 'dart:io';

enum AppPlatform {
  android('Android'),
  ios('iOS'),
  ohos('HarmonyOS'),
  unsupported('Unsupported');

  const AppPlatform(this.displayName);

  final String displayName;

  static AppPlatform get current {
    if (Platform.isAndroid) return AppPlatform.android;
    if (Platform.isIOS) return AppPlatform.ios;
    if (Platform.operatingSystem == 'ohos') return AppPlatform.ohos;
    return AppPlatform.unsupported;
  }
}
