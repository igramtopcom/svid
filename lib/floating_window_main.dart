/// Entry point for the floating capture popup engine.
///
/// This is a SEPARATE Flutter engine spawned by `desktop_multi_window`. It
/// must NOT import the main app (`SsvidApp`) or pull in heavy services
/// (Rust bridge, notifications, tray, sentry). Goal: paint the first frame
/// fast — the popup must feel snappy when the user copies a URL.
///
/// Phase 1A.4 ships the real popup design: Wine Red brand, Inter font,
/// 300×420 portrait layout with thumbnail + preview metadata + action bar
/// (Download / Snooze / Dismiss). The IPC contract is identical to the
/// 1A.3c placeholder — DesktopMultiWindowFloatingWindow on the main side
/// is unchanged.
///
/// Visual states handled:
/// - Video preview with metadata (title + uploader + thumbnail)
/// - Fallback preview (no metadata yet — platform badge + raw URL)
/// - Non-video URL (playlist / channel / search → "Open in SSvid"
///   replaces "Download")
///
/// Out-of-scope here (deferred to a polish slice):
/// - Always-on-top + focus-steal prevention (needs native NSPanel work)
/// - Quota=0 upgrade-premium UI variant
/// - Snooze "feedback" toast on selection
/// - Drag-to-reposition handle
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/brand_config.dart';
import 'core/services/window_geometry_service.dart';
import 'core/theme/app_typography.dart';
import 'features/floating_capture/data/datasources/shared_preferences_window_position_store.dart';
import 'features/floating_capture/domain/entities/popup_action_result.dart';
import 'features/floating_capture/domain/entities/snooze_duration.dart';
import 'features/floating_capture/domain/entities/window_position.dart';
import 'features/floating_capture/domain/services/window_position_store.dart';

// Spec §4.1 dimensions — Portrait 300×420 (collapsed), 300×560 (expanded).
const Size _kCollapsedSize = Size(300, 420);

@visibleForTesting
bool shouldSkipTaskbarForFloatingCapture({String? operatingSystem}) {
  return (operatingSystem ?? Platform.operatingSystem) != 'macos';
}

/// v2.2 Phase 2C — popup state machine. Replaces ad-hoc `_actionTaken`
/// + `_actionResult` fields with a single FSM. Phase transitions go
/// through `_enterPhase` so timer + UI rules are uniformly applied.
enum _PopupPhase {
  /// Default — buttons enabled, idle 60s timer running, no banner.
  idle,

  /// User clicked a terminal action; awaiting [setActionResult] from main.
  /// Pending recovery timer (8s) auto-unlocks if main side aborts silently.
  /// Buttons disabled. Action bar still visible (not banner).
  pending,

  /// Main side reported direct download enqueued. Green banner stays visible
  /// while the download is running; user can dismiss it explicitly.
  resultStarted,

  /// Main side reported download finished. "Play" + "Open folder" + "Close"
  /// actions; final-state auto-close is allowed.
  resultCompleted,

  /// Main side reported download failed. Coral banner with diagnostic +
  /// "Open app for details". No auto-close — user reads + closes.
  resultFailed,

  /// Main side reported video requires authentication (private / members
  /// only). Amber banner + "Open in app" CTA. No auto-close.
  resultAuthRequired,
}

class _PopupPalette {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color placeholder;
  final Color success;
  final Color warning;
  final Color error;

  const _PopupPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.placeholder,
    required this.success,
    required this.warning,
    required this.error,
  });

  Color get accent => BrandConfig.current.popupAccentColor;
  Color get accentForeground => BrandConfig.current.popupAccentForeground;
  Color get accentHover => BrandConfig.current.popupAccentHover;
  Color get accentSoft => accent.withValues(alpha: 0.16);
  Color get accentBorder => accent.withValues(alpha: 0.36);

  static _PopupPalette current() {
    return switch (BrandConfig.current.brand) {
      Brand.svid => const _PopupPalette(
        background: Color(0xFF121214),
        surface: Color(0xFF1A1B20),
        surfaceRaised: Color(0xFF24252C),
        surfaceHover: Color(0xFF2A2B32),
        border: Color(0xFF3B3C45),
        textPrimary: Color(0xFFF7F4F5),
        textSecondary: Color(0xFFC5BEC5),
        textMuted: Color(0xFF8E8790),
        placeholder: Color(0xFF24252C),
        success: Color(0xFF4ADE80),
        warning: Color(0xFFFBBF24),
        error: Color(0xFFF87171),
      ),
      Brand.vidcombo => const _PopupPalette(
        background: Color(0xFF0E1B2C),
        surface: Color(0xFF1A2A40),
        surfaceRaised: Color(0xFF243752),
        surfaceHover: Color(0xFF2D4664),
        border: Color(0xFF38506A),
        textPrimary: Color(0xFFF0F6FA),
        textSecondary: Color(0xFFB7C6D7),
        textMuted: Color(0xFF7F91A6),
        placeholder: Color(0xFF243752),
        success: Color(0xFF5EEAD4),
        warning: Color(0xFFFCD34D),
        error: Color(0xFFFB7185),
      ),
    };
  }
}

// _noop helper removed — reviewer-3 Fix 5: disabled buttons now pass
// null onPressed for proper Material disabled visual. _noop was a fake
// that left buttons looking enabled.

// =============================================================================
// Popup-engine i18n
//
// The popup engine intentionally does NOT import easy_localization to keep
// boot fast (no asset-bundle JSON parsing on the critical path). Instead
// we ship a tiny string table inline. The main app passes the user's
// active locale code via launch args; this resolver looks it up with an
// English fallback so an unknown / future locale renders English rather
// than the raw key.
//
// When adding a string here, also add it to assets/translations/*.json
// under `floatingCapture.popup*` so the Settings UI stays consistent.
// =============================================================================

const Map<String, Map<String, String>> _kPopupStrings = {
  'en': {
    // Brand-aware: {appName} is substituted at lookup time with
    // BrandConfig.current.appName (SSvid / VidCombo) so VidCombo build
    // doesn't show "Open SSvid".
    'menuOpenApp': 'Open {appName}',
    'menuSettings': 'Settings',
    'tooltipMore': 'More',
    'tooltipDismiss': 'Dismiss',
    'tooltipSnooze': 'Snooze',
    'actionDownload': 'Download',
    'actionDownloadNow': 'Download now',
    'actionMoreOptions': 'More options…',
    'actionOpenInApp': 'Open in {appName}',
    'actionWorking': 'Working…',
    // v2.2 Phase 2C — action result banner copy.
    'stateDownloadStartedTitle': 'Saving to Downloads/',
    'stateDownloadCompleteTitle': 'Saved!',
    'stateDownloadFailedTitle': "Couldn't download",
    'stateAuthRequiredTitle': 'Sign-in required',
    'stateAuthRequiredSubtitle': 'Open in {appName} to use saved cookies',
    'actionOpenAppForDetails': 'Open {appName} for details',
    'actionOpenFolder': 'Open folder',
    'actionPlay': 'Play',
    'actionClose': 'Close',
    'queueMore': '+{count} more in queue',
    'queuePosition': '{position} of {total}',
    'snooze30m': '30 minutes',
    'snooze1h': '1 hour',
    'snooze4h': '4 hours',
    'snooze1d': '1 day',
    'snoozeManual': 'Until I resume',
    'quotaRemaining': '{count} captures left today',
  },
  'vi': {
    'menuOpenApp': 'Mở {appName}',
    'menuSettings': 'Cài đặt',
    'tooltipMore': 'Thêm',
    'tooltipDismiss': 'Đóng',
    'tooltipSnooze': 'Tạm dừng',
    'actionDownload': 'Tải',
    'actionDownloadNow': 'Tải ngay',
    'actionMoreOptions': 'Tuỳ chọn…',
    'actionOpenInApp': 'Mở trong {appName}',
    'actionWorking': 'Đang xử lý…',
    // v2.2 Phase 2C — action result banner copy.
    'stateDownloadStartedTitle': 'Đang tải xuống Downloads/',
    'stateDownloadCompleteTitle': 'Tải xong!',
    'stateDownloadFailedTitle': 'Không tải được',
    'stateAuthRequiredTitle': 'Video private',
    'stateAuthRequiredSubtitle':
        'Mở trong {appName} để dùng cookies đã đăng nhập',
    'actionOpenAppForDetails': 'Mở {appName} để xem chi tiết',
    'actionOpenFolder': 'Mở thư mục',
    'actionPlay': 'Phát',
    'actionClose': 'Đóng',
    'queueMore': '+{count} đang chờ',
    'queuePosition': '{position} / {total}',
    'snooze30m': '30 phút',
    'snooze1h': '1 giờ',
    'snooze4h': '4 giờ',
    'snooze1d': '1 ngày',
    'snoozeManual': 'Đến khi tôi bật lại',
    'quotaRemaining': 'Còn {count} lượt hôm nay',
  },
  'es': {
    'menuOpenApp': 'Abrir {appName}',
    'menuSettings': 'Ajustes',
    'tooltipMore': 'Más',
    'tooltipDismiss': 'Descartar',
    'tooltipSnooze': 'Posponer',
    'actionDownload': 'Descargar',
    'actionDownloadNow': 'Descargar ahora',
    'actionMoreOptions': 'Más opciones…',
    'actionOpenInApp': 'Abrir en {appName}',
    'actionWorking': 'Trabajando…',
    'stateDownloadStartedTitle': 'Guardando en Descargas/',
    'stateDownloadCompleteTitle': '¡Guardado!',
    'stateDownloadFailedTitle': 'No se pudo descargar',
    'stateAuthRequiredTitle': 'Inicio de sesión requerido',
    'stateAuthRequiredSubtitle': 'Abre {appName} para usar cookies guardadas',
    'actionOpenAppForDetails': 'Abrir {appName} para más detalles',
    'actionOpenFolder': 'Abrir carpeta',
    'actionPlay': 'Reproducir',
    'actionClose': 'Cerrar',
    'queueMore': '+{count} más en cola',
    'queuePosition': '{position} de {total}',
    'snooze30m': '30 minutos',
    'snooze1h': '1 hora',
    'snooze4h': '4 horas',
    'snooze1d': '1 día',
    'snoozeManual': 'Hasta que lo reanude',
    'quotaRemaining': '{count} capturas restantes hoy',
  },
  'pt': {
    'menuOpenApp': 'Abrir {appName}',
    'menuSettings': 'Configurações',
    'tooltipMore': 'Mais',
    'tooltipDismiss': 'Dispensar',
    'tooltipSnooze': 'Adiar',
    'actionDownload': 'Baixar',
    'actionDownloadNow': 'Baixar agora',
    'actionMoreOptions': 'Mais opções…',
    'actionOpenInApp': 'Abrir no {appName}',
    'actionWorking': 'Processando…',
    'stateDownloadStartedTitle': 'Salvando em Downloads/',
    'stateDownloadCompleteTitle': 'Salvo!',
    'stateDownloadFailedTitle': 'Não foi possível baixar',
    'stateAuthRequiredTitle': 'Login necessário',
    'stateAuthRequiredSubtitle': 'Abra o {appName} para usar cookies salvos',
    'actionOpenAppForDetails': 'Abrir {appName} para detalhes',
    'actionOpenFolder': 'Abrir pasta',
    'actionPlay': 'Reproduzir',
    'actionClose': 'Fechar',
    'queueMore': '+{count} na fila',
    'queuePosition': '{position} de {total}',
    'snooze30m': '30 minutos',
    'snooze1h': '1 hora',
    'snooze4h': '4 horas',
    'snooze1d': '1 dia',
    'snoozeManual': 'Até eu retomar',
    'quotaRemaining': '{count} capturas restantes hoje',
  },
  'ja': {
    'menuOpenApp': '{appName} を開く',
    'menuSettings': '設定',
    'tooltipMore': 'もっと見る',
    'tooltipDismiss': '閉じる',
    'tooltipSnooze': '一時停止',
    'actionDownload': 'ダウンロード',
    'actionDownloadNow': '今すぐダウンロード',
    'actionMoreOptions': 'その他のオプション…',
    'actionOpenInApp': '{appName} で開く',
    'actionWorking': '処理中…',
    'stateDownloadStartedTitle': 'Downloads/ に保存中',
    'stateDownloadCompleteTitle': '保存しました！',
    'stateDownloadFailedTitle': 'ダウンロードできませんでした',
    'stateAuthRequiredTitle': 'サインインが必要',
    'stateAuthRequiredSubtitle': '保存したCookieを使うには {appName} を開いてください',
    'actionOpenAppForDetails': '詳細を見るには {appName} を開く',
    'actionOpenFolder': 'フォルダを開く',
    'actionPlay': '再生',
    'actionClose': '閉じる',
    'queueMore': '+{count} 件待機中',
    'queuePosition': '{position}/{total}',
    'snooze30m': '30分',
    'snooze1h': '1時間',
    'snooze4h': '4時間',
    'snooze1d': '1日',
    'snoozeManual': '再開するまで',
    'quotaRemaining': '今日あと {count} 回キャプチャできます',
  },
  'ko': {
    'menuOpenApp': '{appName} 열기',
    'menuSettings': '설정',
    'tooltipMore': '더보기',
    'tooltipDismiss': '닫기',
    'tooltipSnooze': '잠시 끄기',
    'actionDownload': '다운로드',
    'actionDownloadNow': '지금 다운로드',
    'actionMoreOptions': '추가 옵션…',
    'actionOpenInApp': '{appName}에서 열기',
    'actionWorking': '처리 중…',
    'stateDownloadStartedTitle': 'Downloads/에 저장 중',
    'stateDownloadCompleteTitle': '저장됨!',
    'stateDownloadFailedTitle': '다운로드 실패',
    'stateAuthRequiredTitle': '로그인 필요',
    'stateAuthRequiredSubtitle': '저장된 쿠키를 사용하려면 {appName}을 여세요',
    'actionOpenAppForDetails': '자세히 보려면 {appName} 열기',
    'actionOpenFolder': '폴더 열기',
    'actionPlay': '재생',
    'actionClose': '닫기',
    'queueMore': '+{count}개 대기 중',
    'queuePosition': '{position}/{total}',
    'snooze30m': '30분',
    'snooze1h': '1시간',
    'snooze4h': '4시간',
    'snooze1d': '1일',
    'snoozeManual': '다시 시작할 때까지',
    'quotaRemaining': '오늘 {count}회 캡처 남음',
  },
  'zh': {
    'menuOpenApp': '打开 {appName}',
    'menuSettings': '设置',
    'tooltipMore': '更多',
    'tooltipDismiss': '关闭',
    'tooltipSnooze': '暂停',
    'actionDownload': '下载',
    'actionDownloadNow': '立即下载',
    'actionMoreOptions': '更多选项…',
    'actionOpenInApp': '在 {appName} 中打开',
    'actionWorking': '处理中…',
    'stateDownloadStartedTitle': '正在保存到 Downloads/',
    'stateDownloadCompleteTitle': '已保存！',
    'stateDownloadFailedTitle': '下载失败',
    'stateAuthRequiredTitle': '需要登录',
    'stateAuthRequiredSubtitle': '打开 {appName} 以使用已保存的 cookie',
    'actionOpenAppForDetails': '打开 {appName} 查看详情',
    'actionOpenFolder': '打开文件夹',
    'actionPlay': '播放',
    'actionClose': '关闭',
    'queueMore': '+{count} 在队列',
    'queuePosition': '{position}/{total}',
    'snooze30m': '30 分钟',
    'snooze1h': '1 小时',
    'snooze4h': '4 小时',
    'snooze1d': '1 天',
    'snoozeManual': '直到我恢复',
    'quotaRemaining': '今天还剩 {count} 次捕获',
  },
  'de': {
    'menuOpenApp': '{appName} öffnen',
    'menuSettings': 'Einstellungen',
    'tooltipMore': 'Mehr',
    'tooltipDismiss': 'Schließen',
    'tooltipSnooze': 'Pausieren',
    'actionDownload': 'Herunterladen',
    'actionDownloadNow': 'Jetzt herunterladen',
    'actionMoreOptions': 'Weitere Optionen…',
    'actionOpenInApp': 'In {appName} öffnen',
    'actionWorking': 'Wird bearbeitet…',
    'stateDownloadStartedTitle': 'Wird in Downloads/ gespeichert',
    'stateDownloadCompleteTitle': 'Gespeichert!',
    'stateDownloadFailedTitle': 'Download fehlgeschlagen',
    'stateAuthRequiredTitle': 'Anmeldung erforderlich',
    'stateAuthRequiredSubtitle':
        '{appName} öffnen, um gespeicherte Cookies zu verwenden',
    'actionOpenAppForDetails': '{appName} für Details öffnen',
    'actionOpenFolder': 'Ordner öffnen',
    'actionPlay': 'Abspielen',
    'actionClose': 'Schließen',
    'queueMore': '+{count} weitere in Warteschlange',
    'queuePosition': '{position} von {total}',
    'snooze30m': '30 Minuten',
    'snooze1h': '1 Stunde',
    'snooze4h': '4 Stunden',
    'snooze1d': '1 Tag',
    'snoozeManual': 'Bis ich fortsetze',
    'quotaRemaining': '{count} Aufnahmen heute übrig',
  },
  'fr': {
    'menuOpenApp': 'Ouvrir {appName}',
    'menuSettings': 'Paramètres',
    'tooltipMore': 'Plus',
    'tooltipDismiss': 'Fermer',
    'tooltipSnooze': 'Mettre en pause',
    'actionDownload': 'Télécharger',
    'actionDownloadNow': 'Télécharger maintenant',
    'actionMoreOptions': "Plus d'options…",
    'actionOpenInApp': 'Ouvrir dans {appName}',
    'actionWorking': 'En cours…',
    'stateDownloadStartedTitle': 'Enregistrement dans Téléchargements/',
    'stateDownloadCompleteTitle': 'Enregistré !',
    'stateDownloadFailedTitle': 'Échec du téléchargement',
    'stateAuthRequiredTitle': 'Connexion requise',
    'stateAuthRequiredSubtitle':
        'Ouvrir {appName} pour utiliser les cookies enregistrés',
    'actionOpenAppForDetails': 'Ouvrir {appName} pour les détails',
    'actionOpenFolder': 'Ouvrir le dossier',
    'actionPlay': 'Lire',
    'actionClose': 'Fermer',
    'queueMore': '+{count} de plus en file',
    'queuePosition': '{position} sur {total}',
    'snooze30m': '30 minutes',
    'snooze1h': '1 heure',
    'snooze4h': '4 heures',
    'snooze1d': '1 jour',
    'snoozeManual': "Jusqu'à ce que je reprenne",
    'quotaRemaining': "{count} captures restantes aujourd'hui",
  },
  'ru': {
    'menuOpenApp': 'Открыть {appName}',
    'menuSettings': 'Настройки',
    'tooltipMore': 'Ещё',
    'tooltipDismiss': 'Закрыть',
    'tooltipSnooze': 'Отложить',
    'actionDownload': 'Загрузить',
    'actionDownloadNow': 'Загрузить сейчас',
    'actionMoreOptions': 'Больше опций…',
    'actionOpenInApp': 'Открыть в {appName}',
    'actionWorking': 'Обработка…',
    'stateDownloadStartedTitle': 'Сохраняется в Downloads/',
    'stateDownloadCompleteTitle': 'Сохранено!',
    'stateDownloadFailedTitle': 'Не удалось загрузить',
    'stateAuthRequiredTitle': 'Требуется вход',
    'stateAuthRequiredSubtitle':
        'Откройте {appName}, чтобы использовать сохранённые cookies',
    'actionOpenAppForDetails': 'Открыть {appName} для деталей',
    'actionOpenFolder': 'Открыть папку',
    'actionPlay': 'Воспроизвести',
    'actionClose': 'Закрыть',
    'queueMore': '+{count} в очереди',
    'queuePosition': '{position} из {total}',
    'snooze30m': '30 минут',
    'snooze1h': '1 час',
    'snooze4h': '4 часа',
    'snooze1d': '1 день',
    'snoozeManual': 'Пока не возобновлю',
    'quotaRemaining': 'Сегодня осталось {count} захватов',
  },
  'ar': {
    'menuOpenApp': 'فتح {appName}',
    'menuSettings': 'الإعدادات',
    'tooltipMore': 'المزيد',
    'tooltipDismiss': 'إغلاق',
    'tooltipSnooze': 'إيقاف مؤقت',
    'actionDownload': 'تنزيل',
    'actionDownloadNow': 'تنزيل الآن',
    'actionMoreOptions': 'خيارات أخرى…',
    'actionOpenInApp': 'فتح في {appName}',
    'actionWorking': 'جارٍ المعالجة…',
    'stateDownloadStartedTitle': 'جارٍ الحفظ في Downloads/',
    'stateDownloadCompleteTitle': 'تم الحفظ!',
    'stateDownloadFailedTitle': 'تعذّر التنزيل',
    'stateAuthRequiredTitle': 'تسجيل الدخول مطلوب',
    'stateAuthRequiredSubtitle': 'افتح {appName} لاستخدام الكوكيز المحفوظة',
    'actionOpenAppForDetails': 'افتح {appName} للتفاصيل',
    'actionOpenFolder': 'فتح المجلد',
    'actionPlay': 'تشغيل',
    'actionClose': 'إغلاق',
    'queueMore': '+{count} في قائمة الانتظار',
    'queuePosition': '{position} من {total}',
    'snooze30m': '30 دقيقة',
    'snooze1h': 'ساعة واحدة',
    'snooze4h': '4 ساعات',
    'snooze1d': 'يوم واحد',
    'snoozeManual': 'حتى أستأنف',
    'quotaRemaining': 'متبقي {count} التقاطات اليوم',
  },
  'hi': {
    'menuOpenApp': '{appName} खोलें',
    'menuSettings': 'सेटिंग्स',
    'tooltipMore': 'अधिक',
    'tooltipDismiss': 'बंद करें',
    'tooltipSnooze': 'रोकें',
    'actionDownload': 'डाउनलोड',
    'actionDownloadNow': 'अभी डाउनलोड',
    'actionMoreOptions': 'अधिक विकल्प…',
    'actionOpenInApp': '{appName} में खोलें',
    'actionWorking': 'प्रोसेस हो रहा…',
    'stateDownloadStartedTitle': 'Downloads/ में सहेजा जा रहा',
    'stateDownloadCompleteTitle': 'सहेजा गया!',
    'stateDownloadFailedTitle': 'डाउनलोड नहीं हो सका',
    'stateAuthRequiredTitle': 'साइन इन आवश्यक',
    'stateAuthRequiredSubtitle': 'सहेजी गई कुकीज़ के लिए {appName} खोलें',
    'actionOpenAppForDetails': 'विवरण के लिए {appName} खोलें',
    'actionOpenFolder': 'फ़ोल्डर खोलें',
    'actionPlay': 'चलाएं',
    'actionClose': 'बंद करें',
    'queueMore': '+{count} कतार में',
    'queuePosition': '{total} में से {position}',
    'snooze30m': '30 मिनट',
    'snooze1h': '1 घंटा',
    'snooze4h': '4 घंटे',
    'snooze1d': '1 दिन',
    'snoozeManual': 'जब तक मैं फिर से शुरू न करूं',
    'quotaRemaining': 'आज {count} कैप्चर बाकी',
  },
  'id': {
    'menuOpenApp': 'Buka {appName}',
    'menuSettings': 'Pengaturan',
    'tooltipMore': 'Lainnya',
    'tooltipDismiss': 'Tutup',
    'tooltipSnooze': 'Tunda',
    'actionDownload': 'Unduh',
    'actionDownloadNow': 'Unduh sekarang',
    'actionMoreOptions': 'Opsi lain…',
    'actionOpenInApp': 'Buka di {appName}',
    'actionWorking': 'Memproses…',
    'stateDownloadStartedTitle': 'Menyimpan ke Downloads/',
    'stateDownloadCompleteTitle': 'Tersimpan!',
    'stateDownloadFailedTitle': 'Gagal mengunduh',
    'stateAuthRequiredTitle': 'Login diperlukan',
    'stateAuthRequiredSubtitle':
        'Buka {appName} untuk menggunakan cookie tersimpan',
    'actionOpenAppForDetails': 'Buka {appName} untuk detail',
    'actionOpenFolder': 'Buka folder',
    'actionPlay': 'Putar',
    'actionClose': 'Tutup',
    'queueMore': '+{count} lagi di antrean',
    'queuePosition': '{position} dari {total}',
    'snooze30m': '30 menit',
    'snooze1h': '1 jam',
    'snooze4h': '4 jam',
    'snooze1d': '1 hari',
    'snoozeManual': 'Sampai saya lanjutkan',
    'quotaRemaining': 'Sisa {count} tangkapan hari ini',
  },
  'th': {
    'menuOpenApp': 'เปิด {appName}',
    'menuSettings': 'การตั้งค่า',
    'tooltipMore': 'เพิ่มเติม',
    'tooltipDismiss': 'ปิด',
    'tooltipSnooze': 'หยุดชั่วคราว',
    'actionDownload': 'ดาวน์โหลด',
    'actionDownloadNow': 'ดาวน์โหลดเลย',
    'actionMoreOptions': 'ตัวเลือกเพิ่มเติม…',
    'actionOpenInApp': 'เปิดใน {appName}',
    'actionWorking': 'กำลังดำเนินการ…',
    'stateDownloadStartedTitle': 'กำลังบันทึกไปที่ Downloads/',
    'stateDownloadCompleteTitle': 'บันทึกแล้ว!',
    'stateDownloadFailedTitle': 'ดาวน์โหลดไม่สำเร็จ',
    'stateAuthRequiredTitle': 'ต้องลงชื่อเข้าใช้',
    'stateAuthRequiredSubtitle': 'เปิด {appName} เพื่อใช้คุกกี้ที่บันทึกไว้',
    'actionOpenAppForDetails': 'เปิด {appName} ดูรายละเอียด',
    'actionOpenFolder': 'เปิดโฟลเดอร์',
    'actionPlay': 'เล่น',
    'actionClose': 'ปิด',
    'queueMore': '+{count} รายการในคิว',
    'queuePosition': '{position} จาก {total}',
    'snooze30m': '30 นาที',
    'snooze1h': '1 ชั่วโมง',
    'snooze4h': '4 ชั่วโมง',
    'snooze1d': '1 วัน',
    'snoozeManual': 'จนกว่าจะเริ่มใหม่',
    'quotaRemaining': 'เหลือ {count} แคปเจอร์วันนี้',
  },
  'tr': {
    'menuOpenApp': '{appName} aç',
    'menuSettings': 'Ayarlar',
    'tooltipMore': 'Daha fazla',
    'tooltipDismiss': 'Kapat',
    'tooltipSnooze': 'Beklet',
    'actionDownload': 'İndir',
    'actionDownloadNow': 'Şimdi indir',
    'actionMoreOptions': 'Daha fazla seçenek…',
    'actionOpenInApp': "{appName}'de aç",
    'actionWorking': 'İşleniyor…',
    'stateDownloadStartedTitle': "Downloads/'a kaydediliyor",
    'stateDownloadCompleteTitle': 'Kaydedildi!',
    'stateDownloadFailedTitle': 'İndirilemedi',
    'stateAuthRequiredTitle': 'Oturum açma gerekli',
    'stateAuthRequiredSubtitle':
        'Kayıtlı çerezleri kullanmak için {appName} aç',
    'actionOpenAppForDetails': 'Detaylar için {appName} aç',
    'actionOpenFolder': 'Klasörü aç',
    'actionPlay': 'Oynat',
    'actionClose': 'Kapat',
    'queueMore': 'Sırada +{count} daha',
    'queuePosition': '{position}/{total}',
    'snooze30m': '30 dakika',
    'snooze1h': '1 saat',
    'snooze4h': '4 saat',
    'snooze1d': '1 gün',
    'snoozeManual': 'Devam ettirene kadar',
    'quotaRemaining': 'Bugün {count} yakalama kaldı',
  },
};

class _PopupStrings {
  final String locale;
  const _PopupStrings(this.locale);

  String _lookup(String key) {
    final raw =
        _kPopupStrings[locale]?[key] ?? _kPopupStrings['en']![key] ?? key;
    // Brand-aware substitution: VidCombo build sees its own brand name
    // instead of hardcoded "SSvid". BrandConfig.current is initialized
    // in the popup engine's main() before runFloatingWindow().
    return raw.replaceAll('{appName}', BrandConfig.current.appName);
  }

  String get menuOpenApp => _lookup('menuOpenApp');
  String get menuSettings => _lookup('menuSettings');
  String get tooltipMore => _lookup('tooltipMore');
  String get tooltipDismiss => _lookup('tooltipDismiss');
  String get tooltipSnooze => _lookup('tooltipSnooze');
  String get actionDownload => _lookup('actionDownload');
  String get actionDownloadNow => _lookup('actionDownloadNow');
  String get actionMoreOptions => _lookup('actionMoreOptions');
  String get actionOpenInApp => _lookup('actionOpenInApp');
  String get actionWorking => _lookup('actionWorking');
  // v2.2 Phase 2C — action result banner.
  String get stateDownloadStartedTitle => _lookup('stateDownloadStartedTitle');
  String get stateDownloadCompleteTitle =>
      _lookup('stateDownloadCompleteTitle');
  String get stateDownloadFailedTitle => _lookup('stateDownloadFailedTitle');
  String get stateAuthRequiredTitle => _lookup('stateAuthRequiredTitle');
  String get stateAuthRequiredSubtitle => _lookup('stateAuthRequiredSubtitle');
  String get actionOpenAppForDetails => _lookup('actionOpenAppForDetails');
  String get actionOpenFolder => _lookup('actionOpenFolder');
  String get actionPlay => _lookup('actionPlay');
  String get actionClose => _lookup('actionClose');
  String get snooze30m => _lookup('snooze30m');
  String get snooze1h => _lookup('snooze1h');
  String get snooze4h => _lookup('snooze4h');
  String get snooze1d => _lookup('snooze1d');
  String get snoozeManual => _lookup('snoozeManual');

  String queueMore(int count) =>
      _lookup('queueMore').replaceAll('{count}', count.toString());

  String queuePosition(int position, int total) => _lookup('queuePosition')
      .replaceAll('{position}', position.toString())
      .replaceAll('{total}', total.toString());

  String quotaRemaining(int count) =>
      _lookup('quotaRemaining').replaceAll('{count}', count.toString());
}

/// Run the floating capture popup app. Called from `main()` after the
/// dispatch logic detects this engine's launch arguments contain
/// `windowType: 'floating_capture'`.
Future<void> runFloatingWindow(
  WindowController windowController,
  Map<String, dynamic> launchArgs,
) async {
  final initial = launchArgs['initialPreview'] as Map<String, dynamic>?;
  // Phase 1D: locale comes from the main app's current EasyLocalization
  // state, passed in launchArgs. Unknown locale → English fallback.
  final localeCode = (launchArgs['localeCode'] as String?) ?? 'en';
  final avoidRects = _parseAvoidRects(launchArgs['avoidRects']);

  await _configureWindowChrome(avoidRects: avoidRects);

  // Phase 1C.2: register the drag-position persistence listener once.
  // Has to happen after programmatic positioning so default/collision-aware
  // placement is not mistaken for a user drag.
  windowManager.addListener(_PositionPersistListener());

  runApp(
    _FloatingCaptureApp(
      windowController: windowController,
      initialPreview: initial ?? const <String, dynamic>{},
      strings: _PopupStrings(localeCode),
    ),
  );
}

/// Sets popup size + chrome via window_manager. Errors are swallowed —
/// the popup must paint its first frame even if the chrome init fails on
/// an unsupported platform.
Future<void> _configureWindowChrome({List<Rect> avoidRects = const []}) async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: _kCollapsedSize,
        center: false,
        backgroundColor: Colors.transparent,
        // On macOS, window_manager implements skipTaskbar by changing the
        // whole NSApplication activation policy to .accessory, which hides
        // the main app's Dock/sidebar icon. Windows still needs this flag so
        // the spawned popup stays out of Alt-Tab/taskbar.
        skipTaskbar: shouldSkipTaskbarForFloatingCapture(),
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
    );
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setHasShadow(true);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FloatingCapture] window chrome init failed: $e');
    }
  }
  // Phase 1C.1: ask the native side to apply floating-panel attributes
  // (always-on-top + no-focus-steal). Best-effort — failure on
  // unsupported platforms is logged but doesn't block paint.
  await _applyFloatingPanelAttributes();

  // Phase 1C.2: restore the user's last drag-saved position (if any)
  // so the popup respects the arrangement they chose. First-run /
  // never-dragged falls back to bottom-right, with PiP collision avoidance.
  await _restoreSavedPosition(avoidRects: avoidRects);

  // Phase 1C.2 audit M1: now that size + panel attributes + saved
  // position have all been applied to the still-hidden window, ask
  // the OS to make it visible. Doing show() from the popup side
  // (instead of waiting for the main engine's controller.show())
  // avoids the flicker where the popup appears at the spawn-default
  // location and then snaps to the saved coordinates.
  await _showWhenReady();
}

/// Native channel registered on each popup engine by
/// FloatingCapturePanelPlugin (macOS Swift / Windows C++). Calling
/// `configurePanel` lifts the popup to .statusBar level on macOS and
/// HWND_TOPMOST + WS_EX_NOACTIVATE on Windows.
const _kPanelChannel = MethodChannel('svid.floating_capture.native');

Future<void> _applyFloatingPanelAttributes() async {
  try {
    await _kPanelChannel.invokeMethod<bool>('configurePanel');
  } on MissingPluginException {
    // Linux / unsupported platform — silently degrade. Popup still
    // appears, just doesn't float above other windows.
    if (kDebugMode) {
      debugPrint(
        '[FloatingCapture] panel plugin missing — running in normal-window mode',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FloatingCapture] configurePanel failed: $e');
    }
  }
}

/// Lazily-built store reused for read-on-spawn + write-on-drag. Held at
/// library scope so the WindowListener (which has no reference to Run-
/// FloatingWindow's locals) can access it.
WindowPositionStore? _positionStore;
bool _suppressNextPositionPersist = false;

Future<WindowPositionStore> _getPositionStore() async {
  final cached = _positionStore;
  if (cached != null) return cached;
  final prefs = await SharedPreferences.getInstance();
  final store = SharedPreferencesWindowPositionStore(prefs);
  _positionStore = store;
  return store;
}

/// v2.2 Phase 2D.0: 24pt edge inset for default bottom-right placement.
/// Picked to match macOS Notification Center spacing — popup sits
/// flush with the visible system tray area without touching screen edge.
const double _kDefaultEdgeInset = 24.0;
const double _kPipCollisionGap = 12.0;

List<Rect> _parseAvoidRects(Object? raw) {
  if (raw is! List) return const [];
  final rects = <Rect>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final left = (item['left'] as num?)?.toDouble();
    final top = (item['top'] as num?)?.toDouble();
    final width = (item['width'] as num?)?.toDouble();
    final height = (item['height'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) {
      continue;
    }
    if (width <= 0 || height <= 0) continue;
    rects.add(Rect.fromLTWH(left, top, width, height));
  }
  return rects;
}

Future<List<Rect>> _visibleDisplayBounds() async {
  final displays = await screenRetriever.getAllDisplays();
  return displays
      .map(
        (display) => WindowGeometryService.visibleRect(
          displaySize: display.size,
          visiblePosition: display.visiblePosition,
          visibleSize: display.visibleSize,
        ),
      )
      .toList();
}

Future<Rect?> _primaryVisibleBounds() async {
  try {
    final primary = await screenRetriever.getPrimaryDisplay();
    return WindowGeometryService.visibleRect(
      displaySize: primary.size,
      visiblePosition: primary.visiblePosition,
      visibleSize: primary.visibleSize,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FloatingCapture] primary-display lookup failed: $e');
    }
    return null;
  }
}

/// Compute bottom-right anchor of the primary display.
/// Returns null if screen_retriever fails (Linux/headless).
Future<Offset?> _bottomRightOfPrimaryDisplay() async {
  final visibleBounds = await _primaryVisibleBounds();
  if (visibleBounds == null) return null;
  return WindowGeometryService.bottomRightPosition(
    visibleBounds: visibleBounds,
    windowSize: _kCollapsedSize,
    marginRight: _kDefaultEdgeInset,
    marginBottom: _kDefaultEdgeInset,
  );
}

Future<Rect?> _visibleBoundsForWindow(Offset position) async {
  try {
    final displayBounds = await _visibleDisplayBounds();
    final fallback = await _primaryVisibleBounds();
    if (fallback == null) return null;
    return WindowGeometryService.chooseDisplayForWindow(
      windowBounds: position & _kCollapsedSize,
      displayBounds: displayBounds,
      fallback: fallback,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FloatingCapture] display-bounds lookup failed: $e');
    }
    return _primaryVisibleBounds();
  }
}

Future<Offset> _avoidOverlappingWindows(
  Offset position,
  List<Rect> avoidRects,
) async {
  if (avoidRects.isEmpty) return position;
  final visibleBounds = await _visibleBoundsForWindow(position);
  if (visibleBounds == null) return position;
  return WindowGeometryService.avoidOverlaps(
    preferredPosition: position,
    windowSize: _kCollapsedSize,
    visibleBounds: visibleBounds,
    avoidBounds: avoidRects,
    gap: _kPipCollisionGap,
    margin: _kDefaultEdgeInset,
  );
}

/// v2.2 Phase 2D.0: bounds-check a saved position against any current
/// display. Returns true when the popup at this origin is fully visible
/// on at least one display. Off-screen → false → caller resets to
/// bottom-right default.
Future<bool> _isOnScreen(double x, double y) async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    for (final d in displays) {
      final size = d.visibleSize ?? d.size;
      final origin = d.visiblePosition ?? Offset.zero;
      final inX =
          x >= origin.dx &&
          (x + _kCollapsedSize.width) <= origin.dx + size.width;
      final inY =
          y >= origin.dy &&
          (y + _kCollapsedSize.height) <= origin.dy + size.height;
      if (inX && inY) return true;
    }
    return false;
  } catch (e) {
    // If we can't enumerate displays, fall back to "trust the saved
    // position" — better than reset-to-default on every spawn.
    return true;
  }
}

Future<void> _restoreSavedPosition({List<Rect> avoidRects = const []}) async {
  try {
    final store = await _getPositionStore();
    final saved = await store.read();

    Offset? target;
    if (saved != null && await _isOnScreen(saved.x, saved.y)) {
      target = Offset(saved.x, saved.y);
    } else {
      // First-spawn OR saved position off-screen (display disconnected,
      // resolution changed). Reset to bottom-right primary display.
      target = await _bottomRightOfPrimaryDisplay();
      if (saved != null && target != null && kDebugMode) {
        debugPrint(
          '[FloatingCapture] saved position off-screen, reset to bottom-right',
        );
      }
    }
    if (target == null) return; // headless / unsupported
    target = await _avoidOverlappingWindows(target, avoidRects);
    // Set position BEFORE the popup is visible so the user sees the
    // popup appear at the resolved location instead of jumping there
    // after first paint. windowManager.setPosition on a hidden window
    // doesn't trigger a paint, so this is free.
    _suppressNextPositionPersist = true;
    await windowManager.setPosition(target);
    Timer(const Duration(milliseconds: 500), () {
      _suppressNextPositionPersist = false;
    });
  } catch (e) {
    _suppressNextPositionPersist = false;
    if (kDebugMode) {
      debugPrint('[FloatingCapture] restore position failed: $e');
    }
  }
}

/// Tell the OS to show the popup window now that the chrome is
/// configured (size + panel attributes + position all applied). The
/// main engine also calls `controller.show()` after spawn() returns,
/// but it races the popup's setup; calling show() from the popup side
/// at the end of chrome configuration ensures the window doesn't
/// appear at its default position before snapping to the saved one.
///
/// `windowManager.show()` is idempotent — the main-side controller.show
/// after this is a no-op.
Future<void> _showWhenReady() async {
  try {
    await windowManager.show();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[FloatingCapture] show on ready failed: $e');
    }
  }
}

/// Listener that persists the popup's position whenever the user
/// finishes dragging it. Hooks into the window_manager event stream;
/// onWindowMoved fires AFTER drag end (not during), so the store sees
/// only stable resting positions.
class _PositionPersistListener with WindowListener {
  @override
  void onWindowMoved() {
    if (_suppressNextPositionPersist) {
      _suppressNextPositionPersist = false;
      return;
    }
    _persistCurrentPosition();
  }

  Future<void> _persistCurrentPosition() async {
    try {
      final position = await windowManager.getPosition();
      final store = await _getPositionStore();
      await store.write(WindowPosition(x: position.dx, y: position.dy));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] persist position failed: $e');
      }
    }
  }
}

class _FloatingCaptureApp extends StatelessWidget {
  final WindowController windowController;
  final Map<String, dynamic> initialPreview;
  final _PopupStrings strings;

  const _FloatingCaptureApp({
    required this.windowController,
    required this.initialPreview,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    // RTL Arabic: popup runs in separate isolate without context.locale,
    // so we resolve textDirection from _PopupStrings.locale + the small
    // known-RTL set. (Reviewer Codex Round-8.5 finding: must be code fix,
    // not just visual smoke test.)
    final isRtl = _isRtlLocale(strings.locale);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '${BrandConfig.current.appName} Floating Capture',
      // Wire locale + delegates so Flutter's automatic Directionality
      // (Material/Widgets/Cupertino) picks ar/he/fa/ur as RTL.
      locale: Locale(strings.locale),
      supportedLocales: const [
        Locale('en'),
        Locale('vi'),
        Locale('es'),
        Locale('pt'),
        Locale('ja'),
        Locale('ko'),
        Locale('zh'),
        Locale('de'),
        Locale('fr'),
        Locale('ru'),
        Locale('ar'),
        Locale('hi'),
        Locale('id'),
        Locale('th'),
        Locale('tr'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        canvasColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: Brightness.dark,
          surface: palette.background,
          onSurface: palette.textPrimary,
        ),
        textTheme: AppTypography.textTheme,
        scaffoldBackgroundColor: Colors.transparent,
        popupMenuTheme: PopupMenuThemeData(
          color: palette.surfaceRaised,
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: palette.textPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: palette.border),
          ),
        ),
      ),
      // Explicit Directionality wrapper layered on top of MaterialApp's
      // locale-driven default — belt-and-suspenders because popup engine
      // is the only Flutter app instance for the popup window, and the
      // separate-isolate boot path is fragile.
      builder:
          (context, child) => Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
      home: _FloatingCaptureHome(
        initialPreview: initialPreview,
        strings: strings,
      ),
    );
  }
}

/// Returns true if [localeCode] is a known RTL script locale.
/// Arabic, Hebrew, Persian, Urdu. App currently ships ar; others kept for
/// future expansion. Tested via popup_isRtlLocale_test.dart.
bool _isRtlLocale(String localeCode) {
  return const {'ar', 'he', 'fa', 'ur'}.contains(localeCode.toLowerCase());
}

class _FloatingCaptureHome extends StatefulWidget {
  final Map<String, dynamic> initialPreview;
  final _PopupStrings strings;

  const _FloatingCaptureHome({
    required this.initialPreview,
    required this.strings,
  });

  @override
  State<_FloatingCaptureHome> createState() => _FloatingCaptureHomeState();
}

class _FloatingCaptureHomeState extends State<_FloatingCaptureHome> {
  /// Channel name matches the production [DesktopMultiWindowFloatingWindow].
  static const _channel = WindowMethodChannel('svid.floating_capture');

  /// Codex audit P1 #2: bounded queue with explicit selection. The
  /// queue ALWAYS contains at least the initial preview (seeded in
  /// initState). Index 0 is the oldest; index `_queue.length-1` is the
  /// most-recently-pushed. The user starts viewing index 0 and can
  /// tap a thumbnail in `_QueueThumbnailStrip` to jump to any other
  /// queued item.
  ///
  /// Capacity is hard-capped at [_kMaxQueueSize] — when [pushQueue]
  /// arrives full, the oldest entry is dropped. selectedIndex is
  /// rebased so the user keeps viewing the same logical item where
  /// possible (or shifts down by one if the dropped entry was theirs).
  static const int _kMaxQueueSize = 5;
  final List<_PreviewState> _queue = [];
  int _selectedIndex = 0;

  int _quotaRemaining = -1; // -1 = unlimited

  /// v2.2 Phase 2B Shift 2 Layer 5: idle auto-close timer.
  /// Popup ẩn sau 60s không có user interaction. Pauses while user is
  /// hovering (M1 ultra-review fix — was causing power user friction
  /// reading queue items). Hover exit restarts the timer.
  Timer? _idleTimer;
  bool _isHovering = false;
  static const Duration _kIdleTimeout = Duration(seconds: 60);

  // ===========================================================================
  // v2.2 Phase 2C state machine (post-reviewer-2 audit refactor)
  //
  // Replaces ad-hoc `_actionTaken` + `_actionResult` fields with a single
  // [_PopupPhase] FSM. Every transition has clear timer + UI rules so phase
  // desync (the root cause of Bug #1, #2, #3, #4 in ultra-review-v2) is
  // structurally impossible.
  // ===========================================================================

  /// Current popup phase. Source of truth for: button enabled-state, banner
  /// rendering, timer scheduling.
  _PopupPhase _phase = _PopupPhase.idle;

  /// Last action result received via [setActionResult] IPC. Only valid when
  /// [_phase] is one of the result phases. Null in idle/pending.
  PopupActionResult? _actionResult;

  /// Wall-clock instant the final Completed banner first appeared. Used by
  /// hover-exit logic to compute remaining time of the final auto-close.
  DateTime? _resultShownAt;

  /// User explicitly hid an in-flight/result popup. Late Started/Completed
  /// IPC from the main app must not re-open the window after that action.
  bool _ignoreLateActionResults = false;

  /// Scheduled hide of the popup window — set for final Completed countdown
  /// or by idle timer (60s). Cancelled on every transition.
  Timer? _autoCloseTimer;

  /// Recovery timer set when entering pending phase. If main side never
  /// fires setActionResult (early-return abort, IPC drop), this fires after
  /// 8s and unlocks back to idle so the user can re-interact. Belt-and-
  /// suspenders for early-return cases in startDownload that em can't
  /// enumerate exhaustively.
  Timer? _pendingRecoveryTimer;

  /// Final Completed banner countdown. The in-progress Started banner is not
  /// auto-hidden; only the final state may retreat without a user action.
  static const Duration _kCompletedAutoClose = Duration(seconds: 8);

  /// Last-resort recovery if main side never fires `setActionResult` —
  /// covers IPC drops, main-process abort, untracked early-return guards.
  /// Bumped from 8s to 30s (reviewer-3 Fix 4) because real yt-dlp
  /// extraction can take 10-25s; the previous 8s timeout could unlock
  /// the popup mid-extraction and let the user double-fire.
  ///
  /// 30s is comfortably longer than typical extractions (P99 ~12s for
  /// YouTube/TikTok) yet short enough that a stuck popup auto-recovers
  /// before the idle 60s timer takes over.
  static const Duration _kPendingRecoveryTimeout = Duration(seconds: 30);

  /// Whether [_phase] currently disables PRIMARY action buttons (Tải ngay,
  /// Tuỳ chọn…, Snooze, OpenInApp, etc.). True for pending + result
  /// phases — these buttons make no sense once a result is showing.
  bool get _actionLocked => _phase != _PopupPhase.idle;

  /// Phase 2D.2 (anh Quân Windows feedback): X-close is ALWAYS allowed,
  /// including from `pending`. Previously dismiss was blocked during
  /// pending so users couldn't cancel mid-IPC — but pending lasts up to
  /// 30s on slow extractions and users perceived the locked popup as
  /// "treo / app crash". Letting dismiss go through during pending
  /// hides the popup; the main-side download continues unchanged (the
  /// request was already routed via Riverpod when `onDownloadClicked`
  /// fired). A late `setActionResult` from main side becomes a no-op
  /// because the phase is `idle` by then.
  ///
  /// Reviewer-4 Fix 1 (close-from-result path) is preserved: result
  /// phases keep working too.
  bool get _canDismiss => true;

  /// Whether the action result banner should render in place of the default
  /// action bar.
  bool get _showResultBanner =>
      _phase == _PopupPhase.resultStarted ||
      _phase == _PopupPhase.resultCompleted ||
      _phase == _PopupPhase.resultFailed ||
      _phase == _PopupPhase.resultAuthRequired;

  /// Transition to [next] phase. Cancels all phase-scoped timers + applies
  /// the new phase's timer rule. UI updates via setState.
  void _enterPhase(_PopupPhase next, {PopupActionResult? result}) {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _pendingRecoveryTimer?.cancel();
    _pendingRecoveryTimer = null;

    setState(() {
      _phase = next;
      _actionResult = result;
      if (next == _PopupPhase.resultCompleted) {
        _resultShownAt = DateTime.now();
      } else {
        _resultShownAt = null;
      }
    });

    switch (next) {
      case _PopupPhase.pending:
        // Safety net — main side should fire setActionResult before this.
        _pendingRecoveryTimer = Timer(_kPendingRecoveryTimeout, () {
          if (!mounted) return;
          if (_phase != _PopupPhase.pending) return;
          if (kDebugMode) {
            debugPrint(
              '[FloatingCapture] pending recovery — '
              'main side never fired setActionResult, unlocking',
            );
          }
          _enterPhase(_PopupPhase.idle);
        });
      case _PopupPhase.resultStarted:
        // Downloading/in-progress state must remain visible until the user
        // explicitly closes it or a terminal result replaces it.
        break;
      case _PopupPhase.resultCompleted:
        // Final banner gets a short auto-dismiss; if the user explicitly
        // closed the in-flight popup, setActionResult is ignored before this.
        unawaited(_ensureVisibleForResult());
        _scheduleResultAutoClose(_kCompletedAutoClose);
      case _PopupPhase.idle:
      case _PopupPhase.resultFailed:
      case _PopupPhase.resultAuthRequired:
        // Failed / AuthRequired: no auto-close. User clicks CTA / Đóng.
        break;
    }
  }

  /// Re-show the popup for a terminal Completed result if the OS window is
  /// not visible for a non-user-acknowledged reason. Explicit user hides set
  /// [_ignoreLateActionResults], so they do not re-open here.
  Future<void> _ensureVisibleForResult() async {
    try {
      final visible = await windowManager.isVisible();
      if (!visible) {
        await windowManager.show();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] ensureVisible failed: $e');
      }
    }
  }

  void _scheduleResultAutoClose(Duration duration) {
    _autoCloseTimer?.cancel();
    if (duration <= Duration.zero) {
      _hideViaAutoClose();
      return;
    }
    _autoCloseTimer = Timer(duration, () {
      if (!mounted) return;
      // Auto-close only fires for the final Completed state. Downloading,
      // Failed, and AuthRequired stay until explicit user action.
      if (_phase != _PopupPhase.resultCompleted) {
        return;
      }
      if (_isHovering) return; // hover-exit will reschedule
      _hideViaAutoClose();
    });
  }

  Future<void> _hideViaAutoClose() async {
    try {
      await windowManager.hide();
      // v2.2 Phase 2C P0b: notify main side this was an auto-hide (NOT user
      // dismiss) so it doesn't blocklist the URL but does sync `_visible`.
      await _channel.invokeMethod('onPopupAutoHidden');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] auto-hide failed: $e');
      }
    }
  }

  /// Convenience accessor — the currently focused preview (the one whose
  /// metadata fills the body and whose URL the action buttons emit on).
  /// The queue invariant guarantees this is valid after [initState].
  _PreviewState get _currentPreview => _queue[_selectedIndex];

  @override
  void initState() {
    super.initState();
    // Seed queue with the initial preview so [_currentPreview] is always
    // valid for the rest of the State's lifetime.
    _queue.add(_PreviewState.fromJson(widget.initialPreview));
    _selectedIndex = 0;
    _channel.setMethodCallHandler(_handleCommand);
    _resetIdleTimer();

    // Codex audit P1 #4 fix: signal the main engine that this popup's
    // method handler is now wired. The main side's `spawn()` is
    // awaiting this; without it the very first invokeMethod (e.g., a
    // setQuotaState fired right after spawn) could race past our
    // handler registration and be silently dropped. Fire-and-forget —
    // a delivery failure isn't recoverable from here, and the main
    // side has a 3-second timeout fallback.
    _channel.invokeMethod('popupReady').catchError((Object e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] popupReady invoke failed: $e');
      }
      return null;
    });
  }

  /// Restart the idle countdown. Called on every user activity so an
  /// active user never sees the popup auto-close mid-interaction.
  /// No-op if hovering — hover-pause invariant.
  void _resetIdleTimer() {
    if (_isHovering) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, () async {
      if (!mounted) return;
      // FSM: don't auto-hide if user is mid-action (pending) or banner up.
      // Idle is for the default capture surface only.
      if (_phase != _PopupPhase.idle) return;
      try {
        await windowManager.hide();
        await _channel.invokeMethod('onPopupAutoHidden');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FloatingCapture] idle hide failed: $e');
        }
      }
    });
  }

  void _onHoverEnter() {
    _isHovering = true;
    _idleTimer?.cancel();
  }

  void _onHoverExit() {
    _isHovering = false;
    _resetIdleTimer();
    // Hover-exit only reschedules final Completed countdown. Started is the
    // in-progress state and must not disappear while the download is running.
    if (_resultShownAt != null && _phase == _PopupPhase.resultCompleted) {
      final elapsed = DateTime.now().difference(_resultShownAt!);
      final remaining = _kCompletedAutoClose - elapsed;
      _scheduleResultAutoClose(remaining);
    }
  }

  @override
  void dispose() {
    // Unregister so a late IPC delivery after teardown doesn't try to
    // setState on a disposed widget. Without this, popup-engine hot
    // restart or main-app rapid push could throw
    // "setState() called after dispose()".
    _channel.setMethodCallHandler(null);
    _idleTimer?.cancel();
    _idleTimer = null;
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _pendingRecoveryTimer?.cancel();
    _pendingRecoveryTimer = null;
    super.dispose();
  }

  Future<dynamic> _handleCommand(MethodCall call) async {
    // Belt-and-suspenders: even though dispose() unhooks the handler,
    // an in-flight invocation may already be queued past that point.
    if (!mounted) return null;

    switch (call.method) {
      case 'showPreview':
        if (call.arguments is Map) {
          _ignoreLateActionResults = false;
          _resetIdleTimer(); // v2.2: fresh content → restart 60s countdown
          setState(() {
            // showPreview = "fresh interaction" — replace the queue
            // with this single item, reset selection + action guard.
            _queue
              ..clear()
              ..add(
                _PreviewState.fromJson(
                  (call.arguments as Map).cast<String, dynamic>(),
                ),
              );
            _selectedIndex = 0;
          });
          // v2.2 Phase 2C FSM: showPreview = "fresh content, fresh
          // interaction" — drop any pending/result phase + cancel timers.
          // Single source of truth via _enterPhase, no ad-hoc resets.
          _enterPhase(_PopupPhase.idle);
        }
        return null;

      case 'pushQueue':
        if (call.arguments is Map) {
          _ignoreLateActionResults = false;
          _resetIdleTimer(); // v2.2: queue grew → restart 60s countdown
          final preview = _PreviewState.fromJson(
            (call.arguments as Map).cast<String, dynamic>(),
          );

          // v2.2 anti-spam Layer 2: queue-level dedupe by rawUrl.
          // If URL already in queue, fast-forward selectedIndex to it
          // instead of appending duplicate. Both branches (dedupe AND
          // append) MUST go through _enterPhase(idle) so the UI is
          // consistent — reviewer-2 P2 fix: previously dedupe branch
          // only reset _actionTaken without clearing banner/timers.
          final existingIdx = _queue.indexWhere(
            (p) => p.rawUrl == preview.rawUrl,
          );
          if (existingIdx >= 0) {
            setState(() {
              _selectedIndex = existingIdx;
            });
            _enterPhase(_PopupPhase.idle);
            return null;
          }

          setState(() {
            _queue.add(preview);
            // Codex audit P1 #2: enforce max capacity, drop oldest.
            // Rebase selectedIndex so the user keeps viewing the same
            // logical item where possible.
            while (_queue.length > _kMaxQueueSize) {
              _queue.removeAt(0);
              if (_selectedIndex > 0) {
                _selectedIndex--;
              }
              // If selectedIndex was 0, the dropped item WAS theirs —
              // index 0 still valid (now points to what was item 1).
            }
          });
          // FSM: append new content → drop any pending/result phase.
          _enterPhase(_PopupPhase.idle);
        }
        return null;

      case 'clearQueue':
        setState(() {
          // Keep at least the current item so [_currentPreview] stays
          // valid; the popup is also being hidden by main, so this is
          // mostly cosmetic before teardown.
          if (_queue.length > 1) {
            final keep = _currentPreview;
            _queue
              ..clear()
              ..add(keep);
            _selectedIndex = 0;
          }
        });
        return null;

      case 'setQuotaState':
        if (call.arguments is Map) {
          setState(() {
            _quotaRemaining =
                ((call.arguments as Map)['remaining'] as num?)?.toInt() ?? -1;
          });
        }
        return null;

      case 'setActionResult':
        // v2.2 Phase 2C FSM: main app reports outcome of terminal action.
        // Phase transition driven by result type — _enterPhase handles
        // timers + UI uniformly so there's no Started/Failed asymmetry.
        if (_ignoreLateActionResults) {
          if (kDebugMode) {
            debugPrint(
              '[FloatingCapture] ignored late action result after user hide',
            );
          }
          return null;
        }
        if (call.arguments is Map) {
          final json = (call.arguments as Map).cast<String, dynamic>();
          final result = PopupActionResult.fromJson(json);
          if (result != null) {
            final nextPhase = switch (result) {
              PopupActionStarted() => _PopupPhase.resultStarted,
              PopupActionCompleted() => _PopupPhase.resultCompleted,
              PopupActionFailed() => _PopupPhase.resultFailed,
              PopupActionAuthRequired() => _PopupPhase.resultAuthRequired,
            };
            _enterPhase(nextPhase, result: result);
          }
        }
        return null;

      case 'applyPlacement':
        if (call.arguments is Map) {
          final args = (call.arguments as Map).cast<String, dynamic>();
          await _restoreSavedPosition(
            avoidRects: _parseAvoidRects(args['avoidRects']),
          );
        }
        return null;

      case 'disposeForQuit':
        _idleTimer?.cancel();
        _idleTimer = null;
        _autoCloseTimer?.cancel();
        _autoCloseTimer = null;
        _pendingRecoveryTimer?.cancel();
        _pendingRecoveryTimer = null;
        if (Platform.isWindows) {
          await windowManager.hide();
          return null;
        }
        try {
          await windowManager.destroy();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[FloatingCapture] disposeForQuit destroy failed: $e');
          }
          try {
            await windowManager.hide();
          } catch (hideError) {
            if (kDebugMode) {
              debugPrint(
                '[FloatingCapture] disposeForQuit hide fallback failed: $hideError',
              );
            }
          }
        }
        return null;

      default:
        if (kDebugMode) {
          debugPrint('[FloatingCapture] unknown command: ${call.method}');
        }
        return null;
    }
  }

  // _actionTaken legacy field replaced by _phase FSM (v2.2 Phase 2C
  // post-reviewer-2 refactor). All emit guards now check _actionLocked
  // which is computed from _phase. Single source of truth.

  /// Move focus to a different item in the queue. Tapping any thumbnail
  /// in [_QueueThumbnailStrip] routes here. Subsequent action emits
  /// (Download / OpenInApp) target the newly-selected item via
  /// [_currentPreview]. Idempotent on the same index.
  void _selectQueueItem(int index) {
    if (index == _selectedIndex) return;
    if (index < 0 || index >= _queue.length) return;
    setState(() => _selectedIndex = index);
  }

  /// Hide the OS window from the popup side. Used by every terminal
  /// action so the user gets instant visual feedback instead of waiting
  /// for the main engine's IPC roundtrip. Idempotent on the OS side.
  /// Per Codex audit P0: dismiss had no hide() call, leaving the
  /// window visible while the main engine thought it was hidden.
  Future<void> _hideLocally() async {
    try {
      await windowManager.hide();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] local hide failed: $e');
      }
    }
  }

  Future<void> _emitDownload() async {
    if (_actionLocked) return;
    _ignoreLateActionResults = false;
    // v2.2 Phase 2C FSM: enter pending — popup stays VISIBLE waiting for
    // setActionResult from main side. Recovery timer (8s) auto-unlocks if
    // main side aborts silently (form invalid, archive duplicate, etc.).
    // Do NOT _hideLocally() here — banner needs visible window to render.
    _enterPhase(_PopupPhase.pending);
    await _channel.invokeMethod('onDownloadClicked', {
      'url': _currentPreview.rawUrl,
      'directDownload': true,
    });
  }

  /// v2.2 Phase 2B: secondary "Tuỳ chọn…" — main app pre-fills URL field
  /// + opens Download Options Dialog (legacy v2.1 path). Popup hides
  /// immediately because the dialog will take focus + the user explicitly
  /// asked to "configure", not see a banner. Main-side terminal-hide also
  /// handles this since directDownload=false stays in the predicate.
  Future<void> _emitMoreOptions() async {
    if (_actionLocked) return;
    _ignoreLateActionResults = true;
    _enterPhase(_PopupPhase.pending);
    await _hideLocally();
    await _channel.invokeMethod('onDownloadClicked', {
      'url': _currentPreview.rawUrl,
      'directDownload': false,
    });
  }

  Future<void> _emitOpenInApp() async {
    if (_actionLocked) return;
    _enterPhase(_PopupPhase.pending);
    await _hideLocally();
    await _channel.invokeMethod('onOpenInAppClicked', {
      'url': _currentPreview.rawUrl,
    });
  }

  Future<void> _emitDismiss() async {
    // X-close is always allowed (Phase 2D.2). Decide which signal to
    // send to main side:
    //   - idle phase: user actively says "no, skip this URL" → send
    //     `onPopupDismissed` → main side blocklists URL 60s to suppress
    //     re-spawn on same clipboard contents.
    //   - pending phase: download was already routed via IPC; user is
    //     just hiding the busy popup → treat as acknowledgment, do NOT
    //     blocklist (the URL is now an in-flight download, not a
    //     dismissed capture).
    //   - result phases: same — acknowledgment, NOT blocklist.
    final isAcknowledgment = _phase == _PopupPhase.pending || _showResultBanner;
    if (isAcknowledgment) {
      _ignoreLateActionResults = true;
    }

    _enterPhase(_PopupPhase.idle);
    await _hideLocally();
    await _channel.invokeMethod(
      isAcknowledgment ? 'onPopupAutoHidden' : 'onPopupDismissed',
    );
  }

  /// v2.2 Phase 2C reviewer-4 Fix 2: CTA in `_FailedRow` — "Mở app để xem
  /// chi tiết". Brings main app forward (existing onMenuOpenApp flow) +
  /// closes popup. Bypasses [_actionLocked] because result-phase CTAs
  /// are the legitimate way out of the result banner.
  Future<void> _emitOpenAppFromResult() async {
    if (!_canDismiss) return;
    _enterPhase(_PopupPhase.idle);
    await _hideLocally();
    await _channel.invokeMethod('onMenuOpenApp');
  }

  /// v2.2 Phase 2C reviewer-4 Fix 2: CTA in `_AuthRequiredRow` — "Mở trong
  /// {appName}". Routes via onOpenInAppClicked so main side pre-fills URL
  /// in HomeScreen + opens dialog (with cookies-aware flow).
  Future<void> _emitOpenInAppFromResult() async {
    if (!_canDismiss) return;
    _enterPhase(_PopupPhase.idle);
    await _hideLocally();
    await _channel.invokeMethod('onOpenInAppClicked', {
      'url': _currentPreview.rawUrl,
    });
  }

  /// v2.2 Phase 2D.1 (CPO feedback): _CompletedRow "Mở thư mục" — reveal
  /// the saved file in Finder/Explorer via main-side `Process.run`. Falls
  /// back to opening the parent directory if file vanished.
  Future<void> _emitOpenSavedFolder() async {
    if (!_canDismiss) return;
    final result = _actionResult;
    if (result is! PopupActionCompleted) return;
    _enterPhase(_PopupPhase.idle);
    await _hideLocally();
    await _channel.invokeMethod('onOpenSavedFolder', {
      'path': result.savedPath,
    });
  }

  /// v2.2 Phase 2D.1 (CPO feedback): _CompletedRow "Phát" — open the
  /// downloaded file in the main app's player surface.
  Future<void> _emitPlayFile() async {
    if (!_canDismiss) return;
    final result = _actionResult;
    if (result is! PopupActionCompleted) return;
    _enterPhase(_PopupPhase.idle);
    await _hideLocally();
    await _channel.invokeMethod('onPlayFile', {'path': result.savedPath});
  }

  Future<void> _emitSnooze(SnoozeDuration d) async {
    if (_actionLocked) return;
    _enterPhase(_PopupPhase.pending);
    await _hideLocally();
    await _channel.invokeMethod('onSnoozeSelected', {'duration': d.wireKey});
  }

  Future<void> _emitThumbnailClick() async {
    // Thumbnail click is NOT terminal — opens external browser; popup
    // stays so user can still click Download. No phase transition.
    await _channel.invokeMethod('onThumbnailClicked', {
      'url': _currentPreview.rawUrl,
    });
  }

  Future<void> _emitOpenMainApp() async {
    // Menu-open-app is terminal — user clearly wants the main app.
    if (_actionLocked) return;
    _enterPhase(_PopupPhase.pending);
    await _hideLocally();
    await _channel.invokeMethod('onMenuOpenApp');
  }

  Future<void> _emitOpenSettings() async {
    if (_actionLocked) return;
    _enterPhase(_PopupPhase.pending);
    await _hideLocally();
    await _channel.invokeMethod('onMenuOpenSettings');
  }

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    const popupRadius = 16.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(popupRadius),
      child: Material(
        color: palette.background,
        // v2.2 Phase 2B: hover-pause for idle auto-close. Mouse enter
        // freezes the 60s countdown; mouse exit restarts it. Power user
        // reading queue items doesn't get interrupted.
        child: MouseRegion(
          onEnter: (_) => _onHoverEnter(),
          onExit: (_) => _onHoverExit(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.background,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(popupRadius),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    strings: widget.strings,
                    onMenuOpenApp: _emitOpenMainApp,
                    onMenuOpenSettings: _emitOpenSettings,
                    onDismiss: _emitDismiss,
                  ),
                  Expanded(
                    child: _PreviewBody(
                      preview: _currentPreview,
                      queue: _queue,
                      selectedIndex: _selectedIndex,
                      strings: widget.strings,
                      onThumbnailTap: _emitThumbnailClick,
                      onSelectQueueItem: _selectQueueItem,
                      // Phase 2D.1 Fix A: result-phase banners are vertically tall
                      // (Failed / AuthRequired ≈ 168pt; Completed up to ~150pt
                      // with three CTAs). On the fixed 300×420 popup that
                      // overflows the body if we keep the platform-badge +
                      // 2-line title block + meta line. Hide the title section
                      // when a banner is up — user already has the filename
                      // inside the banner, the thumbnail still anchors visual
                      // identity, no information loss.
                      compact: _showResultBanner,
                    ),
                  ),
                  // v2.2 Phase 2C FSM: render banner only in result phases.
                  // pending phase = action bar with disabled buttons (visual
                  // signal that click registered, awaiting result).
                  if (_showResultBanner && _actionResult != null)
                    _ActionResultBanner(
                      result: _actionResult!,
                      strings: widget.strings,
                      onClose: _emitDismiss,
                      onOpenAppForDetails: _emitOpenAppFromResult,
                      onOpenInApp: _emitOpenInAppFromResult,
                      onOpenSavedFolder: _emitOpenSavedFolder,
                      onPlayFile: _emitPlayFile,
                    )
                  else
                    _ActionBar(
                      urlType: _currentPreview.urlType,
                      quotaRemaining: _quotaRemaining,
                      strings: widget.strings,
                      onDownload: _emitDownload,
                      onMoreOptions: _emitMoreOptions, // v2.2 Phase 2B
                      onOpenInApp: _emitOpenInApp,
                      onSnooze: _emitSnooze,
                      disabled: _actionLocked, // pending or result phase locks
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Header — brand mark + 3-dot menu + close
// =============================================================================

class _Header extends StatelessWidget {
  final _PopupStrings strings;
  final Future<void> Function() onMenuOpenApp;
  final Future<void> Function() onMenuOpenSettings;
  final Future<void> Function() onDismiss;

  const _Header({
    required this.strings,
    required this.onMenuOpenApp,
    required this.onMenuOpenSettings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(bottom: BorderSide(color: palette.border, width: 1)),
      ),
      child: Row(
        children: [
          // Brand mark — 8pt circle dot. v2.2: uses brand-aware
          // popupBrandDot token from BrandConfig (Stitch design system).
          // SSvid: Wine Red (same as primary action — mono-accent palette).
          // VidCombo: Cyan #03BEFE — DISTINCT from primary button (Ocean Blue
          // #0066CC) per "two-color play" Stitch principle (dot=spark,
          // button=mass).
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: BrandConfig.current.popupBrandDot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            // Brand-aware wordmark — resolves to "SSvid" or "VidCombo"
            // per compile-time BRAND dart-define.
            BrandConfig.current.appName,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          PopupMenuButton<_MenuAction>(
            tooltip: strings.tooltipMore,
            color: palette.surfaceRaised,
            iconSize: 16,
            iconColor: palette.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 176),
            onSelected: (action) {
              switch (action) {
                case _MenuAction.openApp:
                  onMenuOpenApp();
                case _MenuAction.openSettings:
                  onMenuOpenSettings();
              }
            },
            itemBuilder:
                (_) => [
                  PopupMenuItem(
                    value: _MenuAction.openApp,
                    height: 36,
                    child: Row(
                      children: [
                        Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          strings.menuOpenApp,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.openSettings,
                    height: 36,
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 14,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          strings.menuSettings,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: strings.tooltipDismiss,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 28,
              maxWidth: 28,
              minHeight: 28,
            ),
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

enum _MenuAction { openApp, openSettings }

// =============================================================================
// Preview body — thumbnail + title + uploader + queue indicator
// =============================================================================

class _PreviewBody extends StatelessWidget {
  final _PreviewState preview;
  final List<_PreviewState> queue;
  final int selectedIndex;
  final _PopupStrings strings;
  final Future<void> Function() onThumbnailTap;
  final void Function(int index) onSelectQueueItem;

  /// Phase 2D.1 Fix A: when `compact = true`, hide the platform badge +
  /// 2-line title + meta block. Used during result-phase to fit a tall
  /// banner (Failed / AuthRequired / Completed with three CTAs) inside
  /// the fixed 300×420 popup window. Thumbnail stays so the user keeps
  /// visual context of which video the action was about.
  final bool compact;

  const _PreviewBody({
    required this.preview,
    required this.queue,
    required this.selectedIndex,
    required this.strings,
    required this.onThumbnailTap,
    required this.onSelectQueueItem,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasQueue = queue.length > 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Thumbnail(preview: preview, onTap: onThumbnailTap),
          if (hasQueue) ...[
            const SizedBox(height: 8),
            _QueueThumbnailStrip(
              queue: queue,
              selectedIndex: selectedIndex,
              strings: strings,
              onSelect: onSelectQueueItem,
            ),
          ],
          if (!compact) ...[
            const SizedBox(height: 12),
            _PlatformBadge(preview: preview),
            const SizedBox(height: 8),
            _TitleSection(preview: preview),
          ],
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final _PreviewState preview;
  final Future<void> Function() onTap;

  const _Thumbnail({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = preview.thumbnailUrl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              url != null && url.isNotEmpty
                  ? _ResilientThumbnail(url: url)
                  : const _ThumbnailFallback(),
        ),
      ),
    );
  }
}

/// v2.2 Phase 2D.0: YouTube `maxresdefault.jpg` returns 404 for older
/// videos that never had a max-resolution thumbnail (e.g. anything pre-
/// ~2010). Previously the popup degraded straight to the placeholder
/// icon; em now retry the canonical `hqdefault.jpg` (which always exists
/// on YouTube CDN) before falling back to placeholder.
///
/// Non-YouTube URLs go directly to the static placeholder on error —
/// other CDNs don't have a uniform fallback path.
class _ResilientThumbnail extends StatefulWidget {
  final String url;
  const _ResilientThumbnail({required this.url});

  @override
  State<_ResilientThumbnail> createState() => _ResilientThumbnailState();
}

class _ResilientThumbnailState extends State<_ResilientThumbnail> {
  static final _ytMaxRes = RegExp(
    r'^(https?://img\.youtube\.com/vi/[^/]+/)maxresdefault\.jpg$',
  );

  late String _currentUrl;
  bool _triedHqFallback = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  @override
  void didUpdateWidget(covariant _ResilientThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      // Different URL means new content (different video) — reset chain.
      _currentUrl = widget.url;
      _triedHqFallback = false;
    }
  }

  void _onError() {
    if (_triedHqFallback) return; // already at fallback OR final placeholder
    final m = _ytMaxRes.firstMatch(_currentUrl);
    if (m == null) {
      // Non-YouTube or non-maxres URL — placeholder is the final state.
      setState(() => _triedHqFallback = true);
      return;
    }
    setState(() {
      _currentUrl = '${m.group(1)}hqdefault.jpg';
      _triedHqFallback = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _currentUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) {
        if (!_triedHqFallback && _ytMaxRes.hasMatch(_currentUrl)) {
          // Schedule retry on next frame — setState mid-build is illegal.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onError();
          });
        }
        return const _ThumbnailFallback();
      },
      loadingBuilder: (ctx, child, loading) {
        if (loading == null) return child;
        return const _ThumbnailFallback(loading: true);
      },
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  final bool loading;
  const _ThumbnailFallback({this.loading = false});

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    return Container(
      color: palette.placeholder,
      child: Center(
        child:
            loading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                )
                : Icon(
                  Icons.movie_outlined,
                  color: palette.textMuted,
                  size: 36,
                ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  final _PreviewState preview;
  const _PlatformBadge({required this.preview});

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final label = _platformLabel(preview.platformWire);
    final typeLabel = _urlTypeLabel(preview.urlType);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            border: Border.all(color: palette.accentBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.accentHover,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (typeLabel != null) ...[
          const SizedBox(width: 6),
          Text(
            typeLabel,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  static String _platformLabel(String wire) {
    switch (wire) {
      case 'youtube':
        return 'YouTube';
      case 'tiktok':
        return 'TikTok';
      case 'vimeo':
        return 'Vimeo';
      case 'twitter':
        return 'X / Twitter';
      case 'reddit':
        return 'Reddit';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'twitch':
        return 'Twitch';
      default:
        return wire.isEmpty ? 'Link' : wire.toUpperCase();
    }
  }

  static String? _urlTypeLabel(String urlType) {
    switch (urlType) {
      case 'video':
        return null; // default — no extra label
      case 'playlist':
        return 'Playlist';
      case 'channel':
        return 'Channel';
      case 'live':
        return 'Live';
      case 'search':
        return 'Search';
      default:
        return null;
    }
  }
}

class _TitleSection extends StatelessWidget {
  final _PreviewState preview;
  const _TitleSection({required this.preview});

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final title = preview.title;
    final uploader = preview.uploader;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (title != null && title.isNotEmpty) ? title : preview.rawUrl,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: palette.textPrimary,
          ),
        ),
        if (uploader != null && uploader.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            uploader,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Codex audit P1 #2 — queue navigation strip (variant 3 from
/// docs/mockups/queue-nav-3.png). Renders up to [_kMaxQueueSize] tiny
/// thumbnails in a horizontal row; the currently-selected one is ringed
/// in Wine Red. Tapping a thumbnail jumps focus to that item — the
/// action bar's Download / Open-in-SSvid will then target the new
/// selection. Counter "X of N" sits at the row's right edge.
///
/// Hidden entirely when there's only one item in the queue (no queue
/// to navigate). The strip is laid out for max-5 capacity but only
/// renders the actual item count — empty trailing slots are not drawn.
class _QueueThumbnailStrip extends StatelessWidget {
  static const double _thumbWidth = 28;
  static const double _thumbHeight = 21;
  static const double _selectedRingPadding = 1;

  final List<_PreviewState> queue;
  final int selectedIndex;
  final _PopupStrings strings;
  final void Function(int index) onSelect;

  const _QueueThumbnailStrip({
    required this.queue,
    required this.selectedIndex,
    required this.strings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    return Container(
      height: _thumbHeight + (_selectedRingPadding * 2) + 10,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.64),
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < queue.length; i++) ...[
            _QueueThumb(
              preview: queue[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
            const SizedBox(width: 4),
          ],
          const Spacer(),
          Text(
            strings.queuePosition(selectedIndex + 1, queue.length),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueThumb extends StatelessWidget {
  final _PreviewState preview;
  final bool selected;
  final VoidCallback onTap;

  const _QueueThumb({
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final url = preview.thumbnailUrl;
    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _QueueThumbnailStrip._thumbWidth,
        height: _QueueThumbnailStrip._thumbHeight,
        child:
            url != null && url.isNotEmpty
                ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => ColoredBox(color: palette.placeholder),
                )
                : ColoredBox(color: palette.placeholder),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(
          _QueueThumbnailStrip._selectedRingPadding,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? palette.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: inner,
      ),
    );
  }
}

// =============================================================================
// Action bar — primary action + snooze
// =============================================================================

class _ActionBar extends StatelessWidget {
  final String urlType;
  final int quotaRemaining;
  final _PopupStrings strings;
  final Future<void> Function() onDownload;
  final Future<void> Function() onMoreOptions; // v2.2 Phase 2B
  final Future<void> Function() onOpenInApp;
  final Future<void> Function(SnoozeDuration) onSnooze;

  /// v2.2 Phase 2C FSM: when in pending/result phase, the action bar
  /// disables button onPressed so a stuck pending state doesn't allow
  /// double-fire. The underlying _PopupPhase guards already prevent emit,
  /// this is the visual confirmation.
  final bool disabled;

  const _ActionBar({
    required this.urlType,
    required this.quotaRemaining,
    required this.strings,
    required this.onDownload,
    required this.onMoreOptions,
    required this.onOpenInApp,
    required this.onSnooze,
    this.disabled = false,
  });

  bool get _isVideoUrl => urlType == 'video' || urlType == 'live';

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quotaRemaining >= 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                strings.quotaRemaining(quotaRemaining),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color:
                      quotaRemaining == 0
                          ? palette.warning
                          : palette.textSecondary,
                  fontWeight:
                      quotaRemaining == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          if (disabled) ...[
            _WorkingHint(strings: strings),
            const SizedBox(height: 8),
          ],
          // v2.2 Phase 2B Shift 1: video URLs get 2-button stack —
          // primary "Tải ngay" (direct download bypassing dialog) +
          // secondary "Tuỳ chọn…" (legacy v2.1 dialog path). Non-video
          // URLs (playlist/channel/search) keep single primary "Open in app"
          // since direct download doesn't apply.
          // v2.2 Phase 2C reviewer-3 Fix 5: pass NULL onPressed when disabled
          // so FilledButton/OutlinedButton render the proper Material
          // disabled visual (greyed bg, lower opacity, no ripple). Previous
          // _noop fake left buttons looking enabled — visual lie.
          if (_isVideoUrl) ...[
            Row(
              children: [
                Expanded(
                  child: _PrimaryButton(
                    icon: Icons.bolt_rounded,
                    label: strings.actionDownloadNow,
                    onPressed: disabled ? null : onDownload,
                  ),
                ),
                const SizedBox(width: 8),
                _SnoozeMenu(
                  strings: strings,
                  onSelected: disabled ? null : onSnooze,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SecondaryButton(
              icon: Icons.tune_rounded,
              label: strings.actionMoreOptions,
              onPressed: disabled ? null : onMoreOptions,
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _PrimaryButton(
                    icon: Icons.open_in_new_rounded,
                    label: strings.actionOpenInApp,
                    onPressed: disabled ? null : onOpenInApp,
                  ),
                ),
                const SizedBox(width: 8),
                _SnoozeMenu(
                  strings: strings,
                  onSelected: disabled ? null : onSnooze,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// v2.2 Phase 2B: secondary action button — outlined / transparent style
/// for "Tuỳ chọn…" (more options dialog path).
class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function()? onPressed;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cb = onPressed;
    final palette = _PopupPalette.current();
    return OutlinedButton.icon(
      onPressed: cb == null ? null : () => cb(),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(36),
        side: BorderSide(color: palette.border, width: 1),
        foregroundColor: palette.textSecondary,
        disabledForegroundColor: palette.textMuted,
        backgroundColor: palette.surfaceRaised.withValues(alpha: 0.46),
        disabledBackgroundColor: palette.surface.withValues(alpha: 0.48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _WorkingHint extends StatelessWidget {
  final _PopupStrings strings;

  const _WorkingHint({required this.strings});

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        border: Border.all(color: palette.accentBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.accentHover,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.actionWorking,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;

  /// v2.2 Phase 2C reviewer-3 Fix 5: nullable. When null, FilledButton
  /// renders standard Material disabled visual (lower opacity, no ripple).
  final Future<void> Function()? onPressed;

  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cb = onPressed;
    final palette = _PopupPalette.current();
    return FilledButton.icon(
      onPressed: cb == null ? null : () => cb(),
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.accentForeground,
        disabledBackgroundColor: palette.surfaceRaised,
        disabledForegroundColor: palette.textMuted,
        minimumSize: const Size.fromHeight(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _SnoozeMenu extends StatelessWidget {
  final _PopupStrings strings;
  final Future<void> Function(SnoozeDuration)? onSelected;
  const _SnoozeMenu({required this.strings, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final cb = onSelected;
    final palette = _PopupPalette.current();
    return PopupMenuButton<SnoozeDuration>(
      tooltip: strings.tooltipSnooze,
      enabled: cb != null,
      onSelected: cb,
      offset: const Offset(0, -200),
      color: palette.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.border),
      ),
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: cb == null ? palette.surface : palette.surfaceRaised,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.snooze,
          size: 18,
          color: cb == null ? palette.textMuted : palette.textSecondary,
        ),
      ),
      itemBuilder:
          (_) => [
            PopupMenuItem(
              value: SnoozeDuration.thirtyMinutes,
              height: 36,
              child: Text(
                strings.snooze30m,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
            ),
            PopupMenuItem(
              value: SnoozeDuration.oneHour,
              height: 36,
              child: Text(
                strings.snooze1h,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
            ),
            PopupMenuItem(
              value: SnoozeDuration.fourHours,
              height: 36,
              child: Text(
                strings.snooze4h,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
            ),
            PopupMenuItem(
              value: SnoozeDuration.oneDay,
              height: 36,
              child: Text(
                strings.snooze1d,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: SnoozeDuration.untilManuallyResumed,
              height: 36,
              child: Text(
                strings.snoozeManual,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
    );
  }
}

// =============================================================================
// _PreviewState — local view-model the popup operates on. Decouples the UI
// from the [VideoPreview] domain class so we don't drag the main app's
// entity hierarchy into the popup engine.
// =============================================================================

class _PreviewState {
  final String rawUrl;
  final String? title;
  final String? uploader;
  final String? thumbnailUrl;

  /// Wire-format strings — popup doesn't import the domain enums to avoid
  /// pulling in classifier code. Header/badge logic lives in this file.
  final String platformWire;
  final String urlType;

  const _PreviewState({
    required this.rawUrl,
    required this.platformWire,
    required this.urlType,
    this.title,
    this.uploader,
    this.thumbnailUrl,
  });

  factory _PreviewState.fromJson(Map<String, dynamic> json) {
    return _PreviewState(
      rawUrl: (json['rawUrl'] as String?) ?? '',
      platformWire: (json['platform'] as String?) ?? '',
      urlType: (json['urlType'] as String?) ?? 'video',
      title: json['title'] as String?,
      uploader: json['uploader'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
}

/// Helper exported for use by `main.dart` dispatch logic.
/// Parses the [WindowController.arguments] JSON safely. Returns null if the
/// args are empty or malformed — caller should treat that as "main window".
Map<String, dynamic>? parseFloatingWindowLaunchArgs(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

/// Test-only visual harness for the floating capture popup.
///
/// This intentionally reuses the same private widgets as production but avoids
/// desktop_multi_window/window_manager so widget tests can render every state at
/// the real 300×420 popup size. Keep this as a visual contract, not a logic
/// simulator.
@visibleForTesting
Widget buildFloatingCaptureVisualHarness({
  required Map<String, dynamic> initialPreview,
  List<Map<String, dynamic>> queue = const <Map<String, dynamic>>[],
  String localeCode = 'en',
  int quotaRemaining = -1,
  bool pending = false,
  PopupActionResult? result,
}) {
  final strings = _PopupStrings(localeCode);
  final palette = _PopupPalette.current();
  final previews =
      <_PreviewState>[
        _PreviewState.fromJson(initialPreview),
        for (final item in queue) _PreviewState.fromJson(item),
      ].take(_FloatingCaptureHomeState._kMaxQueueSize).toList();

  final selectedIndex = previews.isEmpty ? 0 : previews.length - 1;
  final currentPreview =
      previews.isEmpty
          ? const _PreviewState(rawUrl: '', platformWire: '', urlType: 'video')
          : previews[selectedIndex];

  Future<void> noop() async {}

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      canvasColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BrandConfig.current.popupAccentColor,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        textStyle: TextStyle(color: palette.textPrimary),
      ),
    ),
    home: Center(
      child: SizedBox(
        width: _kCollapsedSize.width,
        height: _kCollapsedSize.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    strings: strings,
                    onMenuOpenApp: noop,
                    onMenuOpenSettings: noop,
                    onDismiss: noop,
                  ),
                  Expanded(
                    child: _PreviewBody(
                      preview: currentPreview,
                      queue: previews,
                      selectedIndex: selectedIndex,
                      strings: strings,
                      onThumbnailTap: noop,
                      onSelectQueueItem: (_) {},
                      compact: result != null,
                    ),
                  ),
                  if (result != null)
                    _ActionResultBanner(
                      result: result,
                      strings: strings,
                      onClose: noop,
                      onOpenAppForDetails: noop,
                      onOpenInApp: noop,
                      onOpenSavedFolder: noop,
                      onPlayFile: noop,
                    )
                  else
                    _ActionBar(
                      urlType: currentPreview.urlType,
                      quotaRemaining: quotaRemaining,
                      strings: strings,
                      onDownload: noop,
                      onMoreOptions: noop,
                      onOpenInApp: noop,
                      onSnooze: (_) async {},
                      disabled: pending,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// =============================================================================
// v2.2 Phase 2C — Post-action result banner (State 6/7/8 per Stitch design)
// =============================================================================

/// Renders the popup's action result feedback. Replaces the default
/// [_ActionBar] when [PopupActionResult] is set.
///
/// State variants per Stitch design:
/// - [PopupActionStarted] → Soft Green / Mint banner "Saving to Downloads/" +
///   indeterminate progress bar. Stays visible while the download runs.
/// - [PopupActionCompleted] → Green banner "Saved!" + buttons
///   "Play" + "Open folder" + "Close".
/// - [PopupActionFailed] → Coral banner "Couldn't download" + diagnostic +
///   button "Open app for details".
/// - [PopupActionAuthRequired] → Amber banner "Sign-in required" + button
///   "Open in app".
class _ActionResultBanner extends StatelessWidget {
  final PopupActionResult result;
  final _PopupStrings strings;
  final Future<void> Function() onClose;

  /// Reviewer-4 Fix 2: result-phase CTA dispatchers wired into banner
  /// children. Failed → "Mở app để xem chi tiết"; AuthRequired → "Mở
  /// trong app". Both bypass [_actionLocked] via [_canDismiss] gate.
  final Future<void> Function() onOpenAppForDetails;
  final Future<void> Function() onOpenInApp;

  /// v2.2 Phase 2D.1 (CPO feedback): Completed-phase CTAs that route to
  /// real Finder/Explorer reveal + in-app playback.
  final Future<void> Function() onOpenSavedFolder;
  final Future<void> Function() onPlayFile;

  const _ActionResultBanner({
    required this.result,
    required this.strings,
    required this.onClose,
    required this.onOpenAppForDetails,
    required this.onOpenInApp,
    required this.onOpenSavedFolder,
    required this.onPlayFile,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final palette = _PopupPalette.current();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: switch (r) {
        PopupActionStarted() => _StartedRow(
          filename: r.filename,
          containerRecodeNotice: r.containerRecodeNotice,
          strings: strings,
        ),
        PopupActionCompleted() => _CompletedRow(
          filename: r.filename,
          strings: strings,
          onClose: onClose,
          // Phase 2D.1 (CPO feedback): real CTAs replace the previous
          // onOpenAppForDetails stub. "Mở thư mục" reveals the file in
          // Finder/Explorer; "Phát" opens the in-app player.
          onOpenFolder: onOpenSavedFolder,
          onPlayFile: onPlayFile,
        ),
        PopupActionFailed() => _FailedRow(
          message: r.message,
          errorCode: r.errorCode,
          strings: strings,
          onOpenAppForDetails: onOpenAppForDetails,
          onClose: onClose,
        ),
        PopupActionAuthRequired() => _AuthRequiredRow(
          strings: strings,
          onOpenInApp: onOpenInApp,
          onClose: onClose,
        ),
      },
    );
  }
}

class _StartedRow extends StatelessWidget {
  final String filename;
  final String? containerRecodeNotice;
  final _PopupStrings strings;
  const _StartedRow({
    required this.filename,
    required this.strings,
    this.containerRecodeNotice,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final green = palette.success;
    final warning = palette.warning;
    final recodeNotice = containerRecodeNotice?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.06),
            border: Border.all(color: green.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.stateDownloadStartedTitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (recodeNotice != null && recodeNotice.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: warning.withValues(alpha: 0.08),
              border: Border.all(color: warning.withValues(alpha: 0.28)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sync_rounded, size: 15, color: warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recodeNotice,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      height: 1.25,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Indeterminate progress bar — visual hint that the download is
        // actually running. Real progress lives in the main app's
        // Downloads tab; this is just confirmation feedback.
        SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            backgroundColor: palette.surfaceRaised,
            valueColor: AlwaysStoppedAnimation<Color>(green),
          ),
        ),
      ],
    );
  }
}

class _CompletedRow extends StatelessWidget {
  final String filename;
  final _PopupStrings strings;
  final Future<void> Function() onClose;
  final Future<void> Function() onOpenFolder;
  final Future<void> Function() onPlayFile;
  const _CompletedRow({
    required this.filename,
    required this.strings,
    required this.onClose,
    required this.onOpenFolder,
    required this.onPlayFile,
  });

  @override
  Widget build(BuildContext context) {
    // Phase 2D.1 (CPO feedback): mint-tinted success banner echoes the
    // Started state's confirmation visual but without the live progress
    // bar — the download IS done. Three CTAs in a 2-row layout:
    //   row 1: [Phát]   [Mở thư mục]   ← primary success actions
    //   row 2: [        Đóng        ]   ← clean dismiss
    // Filename header shrunk to a 1-line muted caption so the row stack
    // fits inside the 300×420 popup without overflow.
    final palette = _PopupPalette.current();
    final success = palette.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: success.withValues(alpha: 0.06),
            border: Border.all(color: success.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: success),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.stateDownloadCompleteTitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => onPlayFile(),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(strings.actionPlay),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.accentForeground,
                  minimumSize: const Size.fromHeight(36),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onOpenFolder(),
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: Text(strings.actionOpenFolder),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(36),
                  side: BorderSide(color: palette.border),
                  foregroundColor: palette.textSecondary,
                  backgroundColor: palette.surfaceRaised.withValues(
                    alpha: 0.48,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () => onClose(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(32),
            side: BorderSide(color: palette.border),
            foregroundColor: palette.textSecondary,
            backgroundColor: palette.surfaceRaised.withValues(alpha: 0.34),
          ),
          child: Text(strings.actionClose),
        ),
      ],
    );
  }
}

class _FailedRow extends StatelessWidget {
  final String message;
  final String? errorCode;
  final _PopupStrings strings;
  final Future<void> Function() onOpenAppForDetails;
  final Future<void> Function() onClose;
  const _FailedRow({
    required this.message,
    required this.strings,
    required this.onOpenAppForDetails,
    required this.onClose,
    this.errorCode,
  });

  /// RC8.5: map error code → 2-line user hint. Mirrors the main app's
  /// `errorFeedbackHint(name)` mappings but baked into the floating
  /// popup process so we don't have to import AppLocalizations into
  /// the narrow popup compile graph (popup startup latency budget).
  /// Returns null for unknown codes so the popup falls back to the
  /// generic message + "Open app for details" CTA.
  String? _hintFor(String? code) {
    switch (code) {
      case 'cookieDbLocked':
        return 'Browser cookie database is locked. Close Chrome/Edge '
            'or use in-app login.';
      case 'jsRuntimeUnavailable':
        return 'JavaScript runtime missing. App is re-installing Deno; '
            'retry in a moment.';
      case 'accessDenied':
        return 'Access denied (private / geo-blocked / age-gated). '
            'Open app to sign in or change region.';
      case 'rateLimited':
        return 'Rate limited. Wait a few minutes before retrying.';
      case 'videoNotFound':
        return 'Video not found or has been removed.';
      case 'formatUnavailable':
        return 'No compatible format. Try a different quality or '
            'container.';
      case 'ffmpegError':
        return 'Video conversion failed. Try MP4 or MKV — same video, '
            'no encoder gap.';
      case 'networkOffline':
        return 'No network. Check your connection and retry.';
      case 'networkTimeout':
        return 'Network timeout. Retry, or check your connection.';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final coral = palette.error;
    final hint = _hintFor(errorCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: coral.withValues(alpha: 0.06),
            border: Border.all(color: coral.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 20, color: coral),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.stateDownloadFailedTitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint ?? message,
                      maxLines: hint != null ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => onOpenAppForDetails(),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(strings.actionOpenAppForDetails),
          style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.accentForeground,
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => onClose(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(36),
            side: BorderSide(color: palette.border),
            foregroundColor: palette.textSecondary,
            backgroundColor: palette.surfaceRaised.withValues(alpha: 0.42),
          ),
          child: Text(strings.actionClose),
        ),
      ],
    );
  }
}

class _AuthRequiredRow extends StatelessWidget {
  final _PopupStrings strings;
  final Future<void> Function() onOpenInApp;
  final Future<void> Function() onClose;
  const _AuthRequiredRow({
    required this.strings,
    required this.onOpenInApp,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _PopupPalette.current();
    final amber = palette.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.08),
            border: Border.all(color: amber.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 20, color: amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.stateAuthRequiredTitle,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.stateAuthRequiredSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => onOpenInApp(),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(strings.actionOpenInApp),
          style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.accentForeground,
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => onClose(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(36),
            side: BorderSide(color: palette.border),
            foregroundColor: palette.textSecondary,
            backgroundColor: palette.surfaceRaised.withValues(alpha: 0.42),
          ),
          child: Text(strings.actionClose),
        ),
      ],
    );
  }
}
