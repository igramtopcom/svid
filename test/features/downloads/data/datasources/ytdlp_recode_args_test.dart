import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/services/container_planner.dart';
import 'package:ssvid/features/settings/domain/enums/container_format_preference.dart';

void main() {
  group('force IPv4 policy', () {
    test('keeps legacy network profile for non-TikTok platforms', () {
      expect(
        YtDlpDataSource.usesDefaultNetworkProfileForUrlForTest(
          'https://www.youtube.com/watch?v=abc123',
        ),
        isFalse,
      );
      expect(
        YtDlpDataSource.shouldForceIpv4ForUrlForTest(
          'https://www.youtube.com/watch?v=abc123',
        ),
        isTrue,
      );
      expect(
        YtDlpDataSource.shouldForceIpv4ForUrlForTest(
          'https://www.instagram.com/reel/abc123/',
        ),
        isTrue,
      );
    });

    test('uses yt-dlp default network profile for TikTok hosts', () {
      expect(
        YtDlpDataSource.usesDefaultNetworkProfileForUrlForTest(
          'https://www.tiktok.com/@user/video/7624412140237065486',
        ),
        isTrue,
      );
      expect(
        YtDlpDataSource.shouldForceIpv4ForUrlForTest(
          'https://www.tiktok.com/@user/video/7624412140237065486',
        ),
        isFalse,
      );
      expect(
        YtDlpDataSource.shouldForceIpv4ForUrlForTest(
          'https://vm.tiktok.com/ZMabc123/',
        ),
        isFalse,
      );
      expect(
        YtDlpDataSource.shouldForceIpv4ForUrlForTest(
          'https://vt.tiktok.com/ZMabc123/',
        ),
        isFalse,
      );
    });

    test('strips TikTok browser query params before yt-dlp invocation', () {
      expect(
        YtDlpDataSource.cleanUrlForYtDlpForTest(
          'https://www.tiktok.com/@cinematictravelcontent/video/7624412140237065486?is_from_webapp=1&sender_device=pc',
        ),
        'https://www.tiktok.com/@cinematictravelcontent/video/7624412140237065486',
      );
      expect(
        YtDlpDataSource.cleanUrlForYtDlpForTest(
          'https://m.tiktok.com/@user/video/7624412140237065486?lang=en#share',
        ),
        'https://www.tiktok.com/@user/video/7624412140237065486',
      );
      expect(
        YtDlpDataSource.cleanUrlForYtDlpForTest(
          'https://vm.tiktok.com/ZMabc123/?foo=bar',
        ),
        'https://vm.tiktok.com/ZMabc123/?foo=bar',
      );
    });
  });

  test('MP4 + VP9 emits one --recode-video mp4 snapshot', () {
    const planner = ContainerPlanner();
    final plan = planner.plan(
      pickedContainer: ContainerFormatPreference.mp4,
      sourceVcodec: 'vp9',
      sourceAcodec: 'opus',
    );

    final args = <String>[
      ...YtDlpDataSource.containerPostProcessArgsForTest(
        extractAudio: false,
        videoFormat: 'mp4',
        mergeFormatPriority: plan.mergeFormat,
        remuxVideo: plan.remuxVideo,
        recodeVideo: plan.recodeVideo,
      ),
      ...YtDlpDataSource.forceRemuxArgsForTest(
        forceRemux: true,
        videoFormat: 'mp4',
        recodeVideo: plan.recodeVideo,
        extractAudio: false,
      ),
    ];

    expect(plan.recodeVideo, 'mp4');
    // Wave A: mp4-first runtime prover — the merge lands .mp4 when the
    // delivery is actually native (recode no-ops); falls to mkv and
    // recodes only when genuinely incompatible.
    expect(args, const [
      '--merge-output-format',
      'mp4/mkv/webm',
      '--recode-video',
      'mp4',
    ]);
  });
}
