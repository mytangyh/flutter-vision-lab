import 'package:aicamera/features/camera/camera_detection_page.dart';
import 'package:aicamera/features/detection/cloud/cloud_enriched_detector.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/features/detection/mlkit/mlkit_detector.dart';
import 'package:aicamera/features/detection/mnn/mnn_detector.dart';
import 'package:aicamera/features/detection/yolo/yolo_detector.dart';
import 'package:aicamera/platform/app_platform.dart';
import 'package:aicamera/platform/platform_info.dart';
import 'package:flutter/material.dart';

class ResearchHomePage extends StatefulWidget {
  const ResearchHomePage({super.key});

  @override
  State<ResearchHomePage> createState() => _ResearchHomePageState();
}

class _ResearchHomePageState extends State<ResearchHomePage> {
  late final Future<PlatformInfo> _platform = PlatformInfo.load();

  static final profiles = <DetectionProfile>[
    DetectionProfile(
      id: 'yolo_tflite',
      title: 'YOLO 端侧识别',
      subtitle: 'TFLite · CPU · 当前基线',
      description: '已验证的 YOLOv8n 320 纯端侧链路，作为其他方案的对照组。',
      iconName: 'memory',
      engineFactory: YoloDetector.new,
    ),
    DetectionProfile(
      id: 'yolo_mnn',
      title: 'YOLO · MNN',
      subtitle: 'MNN 3.5 · CPU',
      description: '使用官方 MNN Native API 和同一份 YOLO 模型，比较端侧推理效率。',
      iconName: 'speed',
      supportedPlatforms: const {AppPlatform.android},
      engineFactory: MnnDetector.new,
    ),
    DetectionProfile(
      id: 'mlkit',
      title: 'ML Kit 物体检测',
      subtitle: 'Google ML Kit · Native',
      description: '通用物体检测与粗分类对照；支持 Android 23+ 和 iOS 15.5+。',
      iconName: 'auto_awesome',
      minimumAndroidSdk: 23,
      engineFactory: MlKitDetector.new,
    ),
    DetectionProfile(
      id: 'local_cloud',
      title: '端侧 + 云端精识别',
      subtitle: '平台端侧定位 · 云端 VLM',
      description: 'Android 使用 MNN、iOS 使用 TFLite 定位，稳定后由云端 VLM 补充详情。',
      iconName: 'cloud',
      cloudEnabled: true,
      engineFactory: _createCloudDetector,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AICAMERA 技术预研'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<PlatformInfo>(
        future: _platform,
        builder: (context, snapshot) {
          final platform = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              const _ResearchHeader(),
              const SizedBox(height: 18),
              for (final profile in profiles) ...[
                _ProfileCard(
                  profile: profile,
                  enabled: _isSupported(profile, platform),
                  disabledReason: _disabledReason(profile, platform),
                  onTap: () => _open(profile),
                ),
                const SizedBox(height: 12),
              ],
              if (platform != null)
                Text(
                  '${platform.manufacturer} ${platform.model} · '
                  '${platform.operatingSystem} ${platform.systemVersion} · '
                  '${platform.abi}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _isSupported(DetectionProfile profile, PlatformInfo? platform) {
    final currentPlatform = AppPlatform.current;
    if (!profile.supportedPlatforms.contains(currentPlatform)) {
      return false;
    }
    final minimum = profile.minimumAndroidSdk;
    if (currentPlatform != AppPlatform.android ||
        minimum == null ||
        platform == null ||
        platform.androidSdk == 0) {
      return true;
    }
    return platform.androidSdk >= minimum;
  }

  String? _disabledReason(
    DetectionProfile profile,
    PlatformInfo? platform,
  ) {
    if (_isSupported(profile, platform)) {
      return null;
    }
    final currentPlatform = AppPlatform.current;
    if (!profile.supportedPlatforms.contains(currentPlatform)) {
      return '当前识别链路不支持 ${currentPlatform.displayName}';
    }
    return '需要 Android ${profile.minimumAndroidSdk} 或更高版本';
  }

  Future<void> _open(DetectionProfile profile) async {
    final platform = await _platform;
    if (!_isSupported(profile, platform) || !mounted) {
      return;
    }
    if (profile.cloudEnabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('云端识别说明'),
          content: const Text(
            '该模式会在目标稳定后，将目标区域的压缩裁剪图上传到配置的服务端。'
            '图片只用于本次识别请求；技术预研环境仍需自行确认服务端的数据留存策略。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('同意并继续'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) {
        return;
      }
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CameraDetectionPage(profile: profile),
      ),
    );
  }
}

class _ResearchHeader extends StatelessWidget {
  const _ResearchHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF292348), Color(0xFF151924)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同一输入，四条识别链路',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Flutter 3.27.4 · Android / iOS · 60 秒统一基准报告',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

DetectionEngine _createCloudDetector() {
  final delegate = switch (AppPlatform.current) {
    AppPlatform.android => MnnDetector(),
    AppPlatform.ios => YoloDetector(),
    _ => throw UnsupportedError('当前平台尚未配置云端识别的端侧检测器。'),
  };
  return CloudEnrichedDetector(delegate: delegate);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.enabled,
    required this.disabledReason,
    required this.onTap,
  });

  final DetectionProfile profile;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (profile.iconName) {
      'speed' => Icons.speed,
      'auto_awesome' => Icons.auto_awesome,
      'cloud' => Icons.cloud_outlined,
      _ => Icons.memory,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF141923),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFF7C5CFC).withValues(alpha: 0.18)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: enabled ? const Color(0xFFA99AFC) : Colors.white30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      disabledReason ?? profile.subtitle,
                      style: TextStyle(
                        color:
                            enabled ? const Color(0xFF8BFFCF) : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
