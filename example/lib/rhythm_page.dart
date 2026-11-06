import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rdc_health/rdc_health.dart';

import 'rhythm_notifier.dart';

/// S8: 지난 8주 1시간 단위 걸음으로 걸음 리듬 기준 후보를 되짚어 본다.
/// "이 기준이었다면 지난 8주 동안 며칠 울렸을까"와 오늘 지금 판정을 후보별로 나란히 보여 준다.
class RhythmPage extends StatefulWidget {
  const RhythmPage({super.key});

  @override
  State<RhythmPage> createState() => _RhythmPageState();
}

/// 되짚기 후보. A는 기존 방식(같은 시각 분포로 과다 판정), 나머지는 E 방식(하루 전체 분포)
const candidates = [
  RhythmParams(name: 'A 기존(같은 시각, ±3,000)', highAgainstFullDay: false),
  RhythmNotifier.params,
  RhythmParams(
    name: 'E + 부족 1,000',
    highMinDiff: 1500,
    highMinRatio: 0.25,
    lowMinDiff: 1000,
  ),
];

class _RhythmPageState extends State<RhythmPage> {
  final _health = RdcHealth();
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
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
      final lines = <String>[
        '기간 ${_d(past.keys.isEmpty ? today : past.keys.reduce(_min))} ~ ${_d(today)}, 지난 날 ${past.length}일',
        '',
      ];
      final summary = <String, Object?>{};
      for (final p in candidates) {
        final result = StepRhythm.backtest(past, p);
        final judged = result.where((d) => d.enoughData).toList();
        final high = judged.where((d) => d.highHour != null).toList();
        final low = judged.where((d) => d.low).toList();
        double perWeek(int n) => judged.isEmpty ? 0 : n / judged.length * 7;
        final todayJudge = StepRhythm.judge(
          history: past,
          day: today,
          hour: now.hour,
          today: StepRhythm.cumulativeUntil(days[today] ?? const [], now.hour),
          params: p,
        );
        lines
          ..add(p.name)
          ..add(
            '  판정 가능 ${judged.length}일 / 과다 ${high.length}일(주 ${perWeek(high.length).toStringAsFixed(1)}회) '
            '/ 부족 ${low.length}일(주 ${perWeek(low.length).toStringAsFixed(1)}회)',
          )
          ..add(
            '  오늘 ${now.hour}시까지: ${_kind(todayJudge.kind)} (오늘 ${todayJudge.today}보, '
            '평소 ${todayJudge.usual?.round() ?? '-'}보, 범위 ${todayJudge.lower?.round() ?? '-'}~${todayJudge.upper?.round() ?? '-'})',
          );
        for (final d in high) {
          lines.add('    과다 ${_d(d.day)} ${d.highHour}시 확인, 하루 ${d.total}보');
        }
        for (final d in low) {
          lines.add('    부족 ${_d(d.day)} 19시 기준, 하루 ${d.total}보');
        }
        lines.add('');
        summary[p.name] = {
          'judgedDays': judged.length,
          'highDays': high.length,
          'lowDays': low.length,
          'today': _kind(todayJudge.kind),
        };
      }
      await _health.appendLog('rhythm_backtest', summary);
      // 되짚기 실험(2a, 2c, 4b 등)을 Mac에서 다시 돌릴 수 있게 1시간 단위 원본도 남긴다. 시험 기기 전용
      await _health.appendLog('rhythm_days', {
        for (final MapEntry(key: d, value: h) in days.entries)
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}':
              h,
      });
      setState(() => _text = lines.join('\n'));
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _notify({required bool test}) async {
    try {
      final r = await RhythmNotifier.instance.evaluate(
        trigger: test ? 'test' : 'manual',
        test: test,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '판정: ${r['high']}, 오늘 ${r['todayTotal']}보, 조치: ${r['actions']}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static String _d(DateTime d) =>
      '${d.month}/${d.day}(${'월화수목금토일'[d.weekday - 1]})';
  static String _kind(RhythmKind k) => switch (k) {
    RhythmKind.high => '활동 과다',
    RhythmKind.low => '활동 부족',
    RhythmKind.normal => '평소 범위',
    RhythmKind.notEnoughData => '표본 부족',
  };

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Scaffold(
      appBar: AppBar(
        title: const Text('걸음 리듬 되짚기'),
        actions: [
          // S8 3단계: 확정안으로 오늘 판정 후 예약/취소
          IconButton(
            tooltip: '오늘 판정 실행',
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _notify(test: false),
          ),
          IconButton(
            tooltip: '시험 알림(과다 1분, 부족 2분 뒤)',
            icon: const Icon(Icons.notifications_active),
            onPressed: () => _notify(test: true),
          ),
          if (text != null)
            IconButton(
              tooltip: '결과 복사',
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _error != null
            ? Text(_error!)
            : text == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(child: SelectableText(text)),
      ),
    );
  }
}
