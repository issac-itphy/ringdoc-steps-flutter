import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rdc_health/rdc_health.dart';

import 'rhythm_notifier.dart';
import 'rhythm_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 백그라운드 실행 때 Dart까지 도는지 기록으로 확인
  await RdcHealth().appendLog('dart_main');
  runApp(const MyApp());
  // S8 3단계: 앱이 열리거나 HealthKit이 백그라운드로 실행할 때 걸음 리듬 판정
  unawaited(RhythmNotifier.instance.evaluateSafely('launch'));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: SamplesPage());
}

/// HealthKit 걸음 샘플을 기기와 출처별로 보고, 새 걸음 이벤트가 Flutter로 오는지 보는 시험 화면.
class SamplesPage extends StatefulWidget {
  const SamplesPage({super.key});

  @override
  State<SamplesPage> createState() => _SamplesPageState();
}

class _SamplesPageState extends State<SamplesPage> {
  final _health = RdcHealth();
  final _events = <(DateTime, HealthStepSample)>[];
  StreamSubscription<List<HealthStepSample>>? _subscription;
  Duration _range = const Duration(hours: 3);
  List<HealthStepSample>? _samples;
  String? _message;

  @override
  void initState() {
    super.initState();
    _subscription = _health.stepSampleEvents.listen((samples) {
      // S8 3단계: 새 걸음이 올 때마다(백그라운드 포함) 판정. 10분 안 중복은 건너뜀
      unawaited(RhythmNotifier.instance.evaluateSafely('observer'));
      final now = DateTime.now();
      setState(() => _events.insertAll(0, [for (final s in samples) (now, s)]));
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  Future<void> _load() => _run(() async {
    final to = DateTime.now();
    final samples = await _health.healthStepSamples(to.subtract(_range), to);
    // S9f 근거: 조회 범위와 가장 오래된 기록 시각을 기록 파일에 남긴다
    await _health.appendLog('range_read', {
      'days': _range.inDays,
      'count': samples.length,
      'oldest': samples.isEmpty
          ? null
          : samples
                .map((s) => s.start)
                .reduce((a, b) => a.isBefore(b) ? a : b)
                .toIso8601String(),
    });
    setState(() {
      _samples = samples;
      _message = null;
    });
  });

  @override
  Widget build(BuildContext context) {
    final samples = _samples;
    final countByModel = <String, int>{};
    for (final s in samples ?? const <HealthStepSample>[]) {
      final model = s.deviceModel ?? '기기 정보 없음';
      countByModel[model] = (countByModel[model] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('rdc_health 걸음 시험')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _run(() async {
                  await _health.requestHealthKitAuthorization();
                  await RhythmNotifier.instance.requestPermission();
                  await _load();
                }),
                child: const Text('권한 요청'),
              ),
              OutlinedButton(onPressed: _load, child: const Text('새로고침')),
              OutlinedButton(
                onPressed: () => _run(() async {
                  await _health.enableBackgroundDelivery();
                  setState(() => _message = '백그라운드 전달을 켰습니다');
                }),
                child: const Text('백그라운드 전달 켜기'),
              ),
              OutlinedButton(
                onPressed: () => _run(() => _health.writeTestSteps(50)),
                child: const Text('테스트 걸음 넣기'),
              ),
              // S9f: 45일 전 기록 45보를 넣고 "지난 60일"에 보이는지 확인. Android 전용
              OutlinedButton(
                onPressed: () => _run(() async {
                  await _health.writeTestSteps(45, daysAgo: 45);
                  setState(() => _message = '45일 전 테스트 걸음 45보를 넣었습니다');
                }),
                child: const Text('45일 전 테스트 걸음'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LogPage()),
                ),
                child: const Text('기록 보기'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ComparePage()),
                ),
                child: const Text('비교 표'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RhythmPage()),
                ),
                child: const Text('걸음 리듬'),
              ),
              OutlinedButton(
                onPressed: () => _run(() async {
                  final info = await _health.deviceInfo();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('기기 정보'),
                      content: SelectableText(
                        info.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                      ),
                    ),
                  );
                }),
                child: const Text('기기 정보'),
              ),
              // T1(11/6): 집계 API가 하루 기록 1건을 시간 비율로 나누는지. Android 전용
              OutlinedButton(
                onPressed: () => _run(() async {
                  final check = await _health.aggregateCheck();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('집계 확인'),
                      content: SingleChildScrollView(
                        child: SelectableText(_aggregateText(check)),
                      ),
                    ),
                  );
                }),
                child: const Text('집계 확인'),
              ),
              // T4(11/6): 20분 뒤 알림 예약. 그 전에 걸음이 늘면 주기 작업이 취소한다. Android 전용
              OutlinedButton(
                onPressed: () => _run(() async {
                  await _health.scheduleTestNotification(20);
                  setState(() => _message = '20분 뒤 알림을 예약했습니다');
                }),
                child: const Text('예약 알림(+20분)'),
              ),
              OutlinedButton(
                onPressed: () => _run(() async {
                  await _health.scheduleTestNotification(40);
                  setState(() => _message = '40분 뒤 알림을 예약했습니다');
                }),
                child: const Text('예약 알림(+40분)'),
              ),
              // 11/6 오후: 본 앱 방식(alarmClock)이 Android 12 권한과 삼성 절전 상태 앱에서 뜨는지
              OutlinedButton(
                onPressed: () => _run(() async {
                  final ok = await _health.scheduleTestNotification(
                    5,
                    alarmClock: true,
                  );
                  setState(
                    () => _message = ok
                        ? '5분 뒤 알람시계 방식으로 예약했습니다'
                        : '정확한 알람 권한이 없어 예약하지 못했습니다',
                  );
                }),
                child: const Text('알람시계 예약(+5분)'),
              ),
              SegmentedButton<Duration>(
                segments: const [
                  ButtonSegment(
                    value: Duration(hours: 3),
                    label: Text('최근 3시간'),
                  ),
                  ButtonSegment(value: Duration(days: 7), label: Text('지난 7일')),
                  // 30일 넘은 기록이 읽히는지(Android 과거 기록 권한) 확인용
                  ButtonSegment(
                    value: Duration(days: 60),
                    label: Text('지난 60일'),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: (selected) {
                  setState(() => _range = selected.first);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_message != null) Text(_message!),
          Text('실시간 이벤트 (${_events.length})', style: _heading),
          if (_events.isEmpty) const Text('아직 받은 이벤트 없음'),
          for (final (received, s) in _events.take(20))
            ListTile(
              dense: true,
              title: Text('${s.count}보   받은 시각 ${_time(received)}'),
              subtitle: Text(
                '${_time(s.start)} ~ ${_time(s.end)} / ${s.sourceName}',
              ),
            ),
          const Divider(),
          Text('샘플', style: _heading),
          if (samples != null) ...[
            Text(
              '기기 모델별 샘플 수: '
              '${countByModel.entries.map((e) => '${e.key} ${e.value}개').join(', ')}',
            ),
            if (samples.isEmpty) const Text('샘플 없음(권한 거부일 수도 있음)'),
            for (final s in samples.reversed)
              ListTile(
                dense: true,
                title: Text(
                  '${_time(s.start)} ~ ${_time(s.end)}   ${s.count}보',
                ),
                subtitle: Text(
                  '${[?s.deviceType, s.deviceModel ?? '기기 정보 없음'].join(' ')} / ${s.sourceName}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 네이티브가 기기 안 파일에 남긴 실행 기록.
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final _health = RdcHealth();
  List<HealthLogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _health.readLog();
    setState(() => _entries = entries.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기록'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '기록 복사',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(
              ClipboardData(text: _entries.map(_line).join('\n')),
            ),
          ),
          IconButton(
            tooltip: '기록 지우기',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await _health.clearLog();
              await _load();
            },
          ),
        ],
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('기록 없음'))
          : ListView(
              children: [
                for (final e in _entries)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${_time(e.at, seconds: true)}  ${e.event}  '
                      '${e.appState}${e.protectedData ? '' : '  잠금'}',
                    ),
                    subtitle: e.detail.isEmpty
                        ? null
                        : Text(
                            jsonEncode(e.detail),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
              ],
            ),
    );
  }
}

/// 최근 3시간을 5분 칸으로 나눠 CoreMotion과 HealthKit(iPhone, 워치) 걸음을 나란히 본다.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final _health = RdcHealth();
  bool? _pedometerAvailable;
  List<SlotComparison> _rows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    // 칸 경계를 5분 단위로 맞춤
    final to = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute - now.minute % 5,
    ).add(const Duration(minutes: 5));
    final from = to.subtract(const Duration(hours: 3));
    // HealthKit 권한 전이면 HealthKit 조회만 실패하므로 CoreMotion 결과는 따로 보여 준다
    String? error;
    var health = const <HealthStepSample>[];
    try {
      health = await _health.healthStepSamples(from, to);
    } catch (e) {
      error = 'HealthKit: $e';
    }
    try {
      final available = await _health.isStepCountingAvailable();
      final rows = compareSlots(
        pedometer: await _health.stepBuckets(
          from,
          to,
          const Duration(minutes: 5),
        ),
        health: health,
        from: from,
        to: to,
      );
      setState(() {
        _pedometerAvailable = available;
        _rows = rows.reversed.toList();
        _error = error;
      });
    } catch (e) {
      setState(() => _error = [?error, 'CoreMotion: $e'].join('\n'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nonZero = _rows.where(
      (r) => r.pedometerSteps + r.healthIphoneSteps + r.healthWatchSteps > 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('비교 표 (최근 3시간, 5분 칸)'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_pedometerAvailable == false)
            const Text('CoreMotion: 사용 불가(걸음 센서 없음)'),
          const Text(
            '시각   CoreMotion   HK iPhone 등   HK Watch',
            style: _heading,
          ),
          if (_rows.isNotEmpty && nonZero.isEmpty) const Text('모든 칸이 0보'),
          for (final r in nonZero)
            Text(
              '${_time(r.start)}   '
              '${_pedometerAvailable == false ? '-' : r.pedometerSteps}   '
              '${r.healthIphoneSteps}   ${r.healthWatchSteps}',
            ),
        ],
      ),
    );
  }
}

String _line(HealthLogEntry e) =>
    '${e.at.toIso8601String()} ${e.event} ${e.appState} '
    'protectedData=${e.protectedData} ${jsonEncode(e.detail)}';

const _heading = TextStyle(fontWeight: FontWeight.bold);

String _time(DateTime t, {bool seconds = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  return seconds ? '$hm:${two(t.second)}' : hm;
}

/// 집계 확인 결과를 한눈에: 오늘 집계, 기록 단건, 1시간 단위 집계.
String _aggregateText(Map<String, Object?> check) {
  DateTime at(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch((ms as num?)?.toInt() ?? 0);
  final records = (check['records'] as List?) ?? const [];
  final hourly = (check['hourly'] as List?) ?? const [];
  return [
    '오늘 00:00~지금 집계: ${check['aggregateToday'] ?? '없음'}보',
    '',
    '기록 단건 ${records.length}개',
    for (final r in records.cast<Map>())
      '  ${_time(at(r['start']))} ~ ${_time(at(r['end']))}  '
          '${r['count']}보  ${r['source']}',
    '',
    '1시간 단위 집계',
    for (final h in hourly.cast<Map>())
      '  ${at(h['start']).hour.toString().padLeft(2, '0')}시  ${h['steps'] ?? 0}보',
  ].join('\n');
}
