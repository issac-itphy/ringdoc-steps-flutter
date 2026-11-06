import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rdc_health/rdc_health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// S8 3단계: 걸음 리듬 판정 결과로 로컬 알림을 예약하고 취소한다(iPhone 시험용).
/// 규칙은 planning/2026-11-06-ringdocbiz-s8-3-notification.md의 "예약과 취소".
/// shortcut: 하루 1회 상한과 다른 알림과의 우선순위는 빠져 있음, 본 앱 M1 공통 기반(NotificationBudget)에서 처리
class RhythmNotifier {
  RhythmNotifier._();
  static final instance = RhythmNotifier._();

  static const highId = 101;
  static const lowId = 102;

  /// 2026-11-06 결정: 과다 E 방식(하루 전체 분포), 부족 max(500보, 평소의 10%).
  static const params = RhythmParams(
    name: '확정안',
    highMinDiff: 1500,
    highMinRatio: 0.25,
    lowMinDiff: 500,
    lowMinRatio: 0.10,
  );

  /// 과다 예약 뒤 걸음이 이만큼 더 늘면 아직 걷는 중으로 보고 30분 미룬다.
  static const deferSteps = 300;

  // 저장 키 _v2: 11/6 첫 빌드가 권한 전 실패한 예약도 "오늘 끝"으로 저장한 것을 버리려고 바꿈

  final _plugin = FlutterLocalNotificationsPlugin();
  final _health = RdcHealth();
  bool _ready = false;
  DateTime? _lastObserverRun;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      const InitializationSettings(
        // 권한은 "권한 요청" 버튼에서 따로 묻는다
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<bool?> requestPermission() async {
    await _init();
    return _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
  }

  /// 앱이 열릴 때, HealthKit이 깨울 때, 버튼으로 부른다.
  /// [test]면 판정과 상관없이 과다 1분 뒤, 부족 2분 뒤로 예약한다(알림 경로 확인용).
  Future<Map<String, Object?>> evaluate({
    required String trigger,
    bool test = false,
  }) async {
    await _init();
    final now = DateTime.now();
    if (trigger == 'observer') {
      // 관찰 쿼리는 짧은 간격으로 여러 번 올 수 있다
      final last = _lastObserverRun;
      if (last != null && now.difference(last) < const Duration(minutes: 10)) {
        return const {};
      }
      _lastObserverRun = now;
    }
    final today = DateTime(now.year, now.month, now.day);
    final buckets = await _health.healthStepBuckets(
      today.subtract(const Duration(days: 56)),
      now,
      const Duration(hours: 1),
    );
    final days = <DateTime, List<int>>{};
    for (final b in buckets) {
      final day = DateTime(b.start.year, b.start.month, b.start.day);
      (days[day] ??= List.filled(24, 0))[b.start.hour] += b.steps;
    }
    final past = {...days}..remove(today);
    final todayTotal = StepRhythm.cumulativeUntil(days[today] ?? const [], 24);
    final high = StepRhythm.judge(
      history: past,
      day: today,
      hour: now.hour,
      today: todayTotal,
      params: params,
      highOnly: true,
    );
    final low = StepRhythm.judge(
      history: past,
      day: today,
      hour: params.lowJudgeHour,
      today: todayTotal,
      params: params,
      lowOnly: true,
    );
    final prefs = await SharedPreferences.getInstance();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    final pending = {
      for (final p in await _plugin.pendingNotificationRequests()) p.id,
    };
    final actions = <String>[];

    if (test) {
      await _schedule(highId, now.add(const Duration(minutes: 1)), high: true);
      await _schedule(lowId, now.add(const Duration(minutes: 2)), high: false);
      actions.add('test_scheduled');
    } else {
      // 활동 과다: 처음 확인되면 지금+30분, 걷는 중이면 미룸, 21시 뒤로는 보내지 않음
      final at = now.add(const Duration(minutes: 30));
      final quiet =
          at.hour >= params.lastSendHour || at.hour < params.firstSendHour;
      if (pending.contains(highId)) {
        final last = prefs.getInt('rhythm_high_total_v2') ?? todayTotal;
        if (todayTotal - last >= deferSteps && !quiet) {
          await _schedule(highId, at, high: true);
          await prefs.setInt('rhythm_high_total_v2', todayTotal);
          actions.add('high_deferred');
        }
      } else if (high.kind == RhythmKind.high &&
          prefs.getString('rhythm_high_day_v2') != dayKey &&
          !quiet) {
        if (await _scheduleConfirmed(highId, at, high: true)) {
          await prefs.setString('rhythm_high_day_v2', dayKey);
          await prefs.setInt('rhythm_high_total_v2', todayTotal);
          actions.add('high_scheduled');
        } else {
          actions.add('high_not_accepted');
        }
      }

      // 활동 부족: 매일 처음 확인 때 19:30 예약, 오늘 누적이 부족 경계를 넘으면 취소
      final boundary = low.lowBoundary;
      final lowAt = today.add(const Duration(hours: 19, minutes: 30));
      if (low.kind == RhythmKind.notEnoughData) {
        actions.add('low_not_enough_data');
      } else if (prefs.getString('rhythm_low_day_v2') != dayKey) {
        if (!now.isBefore(lowAt) || todayTotal >= boundary!) {
          await prefs.setString('rhythm_low_day_v2', dayKey);
        } else if (await _scheduleConfirmed(lowId, lowAt, high: false)) {
          await prefs.setString('rhythm_low_day_v2', dayKey);
          actions.add('low_scheduled');
        } else {
          // 알림 권한 전이면 iOS가 예약을 받지 않는다. 다음 판정 때 다시 시도
          actions.add('low_not_accepted');
        }
      } else if (pending.contains(lowId) && todayTotal >= boundary!) {
        await _plugin.cancel(lowId);
        actions.add('low_cancelled');
      }
    }

    final detail = <String, Object?>{
      'trigger': trigger,
      'test': test,
      'todayTotal': todayTotal,
      'high': high.kind.name,
      'highUsual': high.highUsual?.round(),
      'highUpper': high.highUpper?.round(),
      'lowBoundary': low.lowBoundary?.round(),
      'samples': low.samples,
      'pending': pending.toList(),
      'actions': actions,
    };
    await _health.appendLog('rhythm_evaluated', detail);
    return detail;
  }

  /// 앱 시작과 걸음 이벤트에서 부르는 판정. 잠긴 상태 등으로 실패하면 기록만 남긴다.
  Future<void> evaluateSafely(String trigger) async {
    // Android는 삼성 헬스 시간대별 값이 시간 비율로 나뉘어(T1) 판정이 의미 없음. iPhone만
    if (!Platform.isIOS) return;
    try {
      await evaluate(trigger: trigger);
    } catch (e) {
      await _health.appendLog('rhythm_error', {
        'trigger': trigger,
        'error': '$e',
      });
    }
  }

  /// 예약 뒤 iOS 대기 목록에 실제로 들어갔는지 확인한다. 권한 전에는 조용히 빠진다(2026-11-06 발견).
  Future<bool> _scheduleConfirmed(
    int id,
    DateTime at, {
    required bool high,
  }) async {
    await _schedule(id, at, high: high);
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((p) => p.id == id);
  }

  Future<void> _schedule(int id, DateTime at, {required bool high}) async {
    // 문구는 관찰 내용 없이 권유형(구현 설계 "걸음 리듬 알림" 절). 최종 문구는 요청자 승인 대상
    await _plugin.zonedSchedule(
      id,
      high ? '발목과 다리를 풀어 볼까요' : '목과 어깨를 풀어 볼까요',
      high ? '3분 스트레칭으로 다리를 가볍게 풀어 보세요' : '자리에서 3분, 목과 어깨를 천천히 풀어 보세요',
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails('rhythm', '걸음 리듬'),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
