import 'package:flutter/material.dart';
import 'package:rdc_health/rdc_health.dart';

// 결정: 핸들러는 최상위 함수여야 하고 AOT에서 지워지지 않게 entry-point를 붙인다
@pragma('vm:entry-point')
Future<void> onWake() async => debugPrint('rdc_health onWake');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: HealthPage());
}

// 결정: 화면 하나에 8개 호출을 버튼으로 두고 결과는 로그 한 줄씩 쌓는다. 시험용 고정 사용자 ID
const _testUserId = 'example-user';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final _health = RdcHealth();
  final _lines = <String>[];
  bool _active = true;

  Future<void> _run(String name, Future<Object?> Function() call) async {
    String result;
    try {
      result = '${await call()}';
    } catch (e) {
      result = '오류 $e';
    }
    setState(() => _lines.insert(0, '$name: $result'));
  }

  DateTimeRange get _today {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <(String, Future<Object?> Function())>[
      ('availability', _health.availability),
      ('requestPermissions', _health.requestPermissions),
      ('enable', () => _health.enable(_testUserId)),
      ('setBackgroundHandler', () => _health.setBackgroundHandler(onWake)),
      (
        'moveSegments(오늘)',
        () async => (await _health.moveSegments(_today.start, _today.end))
            .map(
              (s) =>
                  '${s.start.hour}:${s.start.minute} ${s.steps}보 ${s.source}',
            )
            .toList(),
      ),
      (
        'hourlySteps(오늘)',
        () async => (await _health.hourlySteps(
          _today.start,
          _today.end,
        )).map((h) => '${h.hourStart.hour}시 ${h.steps}보').toList(),
      ),
      ('disable', _health.disable),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('rdc_health')),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (name, call) in buttons)
                ElevatedButton(
                  onPressed: () => _run(name, call),
                  child: Text(name),
                ),
              SwitchListTile(
                title: const Text('setActive'),
                value: _active,
                onChanged: (v) {
                  setState(() => _active = v);
                  _run('setActive($v)', () => _health.setActive(v));
                },
              ),
            ],
          ),
          Expanded(
            child: ListView(children: [for (final l in _lines) Text(l)]),
          ),
        ],
      ),
    );
  }
}
