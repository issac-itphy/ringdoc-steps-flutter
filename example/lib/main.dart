import 'package:flutter/material.dart';
import 'package:rdc_health/rdc_health.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: SamplesPage());
}

/// HealthKit 걸음 샘플을 기기와 출처별로 보는 시험 화면.
class SamplesPage extends StatefulWidget {
  const SamplesPage({super.key});

  @override
  State<SamplesPage> createState() => _SamplesPageState();
}

class _SamplesPageState extends State<SamplesPage> {
  final _health = RdcHealth();
  Duration _range = const Duration(hours: 3);
  List<HealthStepSample>? _samples;
  String? _error;

  Future<void> _requestAuthorization() async {
    try {
      await _health.requestHealthKitAuthorization();
    } catch (e) {
      setState(() => _error = '$e');
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    final to = DateTime.now();
    try {
      final samples = await _health.healthStepSamples(to.subtract(_range), to);
      setState(() {
        _samples = samples;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

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
                onPressed: _requestAuthorization,
                child: const Text('권한 요청'),
              ),
              OutlinedButton(onPressed: _load, child: const Text('새로고침')),
              SegmentedButton<Duration>(
                segments: const [
                  ButtonSegment(
                    value: Duration(hours: 3),
                    label: Text('최근 3시간'),
                  ),
                  ButtonSegment(value: Duration(days: 7), label: Text('지난 7일')),
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
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
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
                  '${s.deviceModel ?? '기기 정보 없음'} / ${s.sourceName}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _time(DateTime t) =>
    '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';
