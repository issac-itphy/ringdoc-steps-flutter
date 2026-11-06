import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/src/step_rhythm.dart';

/// 하루 [total]보를 08~19시 12칸에 고르게 나눈 1시간 단위 걸음.
List<int> spread(int total) => [
  for (var h = 0; h < 24; h++) (h >= 8 && h < 20) ? total ~/ 12 : 0,
];

/// 2026-11-06(금) 전 평일 [n]일. 하루 걸음은 [totals]를 돌려 쓴다.
HourlyDays weekdays(int n, List<int> totals, {DateTime? until}) {
  final days = <DateTime, List<int>>{};
  var d = until ?? DateTime(2026, 11, 6);
  var i = 0;
  while (days.length < n) {
    d = d.subtract(const Duration(days: 1));
    if (StepRhythm.isWeekend(d)) continue;
    days[d] = spread(totals[i++ % totals.length]);
  }
  return days;
}

void main() {
  const params = RhythmParams(name: '기존 ±3,000');
  final friday = DateTime(2026, 11, 6);

  test('선형 보간 백분위', () {
    expect(StepRhythm.percentile([1, 2, 3, 4, 5], 0.5), 3);
    expect(StepRhythm.percentile([0, 10], 0.1), 1);
  });

  test('평일 표본이 10일보다 적으면 판정하지 않는다', () {
    final j = StepRhythm.judge(
      history: weekdays(9, [6000]),
      day: friday,
      hour: 19,
      today: 100,
      params: params,
    );
    expect(j.kind, RhythmKind.notEnoughData);
  });

  test('하루 500보 미만인 날은 평소 범위에서 뺀다', () {
    final history = weekdays(10, [6000]);
    history[history.keys.first] = spread(300);
    final j = StepRhythm.judge(
      history: history,
      day: friday,
      hour: 19,
      today: 100,
      params: params,
    );
    expect(j.samples, 9);
    expect(j.kind, RhythmKind.notEnoughData);
  });

  test('평소보다 3,000보 넘게 많고 상위 10%를 넘으면 활동 과다', () {
    final j = StepRhythm.judge(
      history: weekdays(20, [5000, 6000, 7000]),
      day: friday,
      hour: 20,
      today: 10000,
      params: params,
    );
    expect(j.kind, RhythmKind.high);
  });

  test('하위 10% 미만이어도 3,000보 차이가 안 나면 기존 기준은 부족이 아니고, 500보 기준은 부족', () {
    final history = weekdays(20, [3000, 3500, 4000]);
    // 19시까지 평소(중앙값) 3,500보 근처, 오늘 2,500보
    final old = StepRhythm.judge(
      history: history,
      day: friday,
      hour: 19,
      today: 2500,
      params: params,
    );
    final lowered = StepRhythm.judge(
      history: history,
      day: friday,
      hour: 19,
      today: 2500,
      params: const RhythmParams(name: '부족 500', lowMinDiff: 500),
    );
    expect(old.kind, RhythmKind.normal);
    expect(lowered.kind, RhythmKind.low);
  });

  test('E 방식: 아침에 평소 같은 시각보다 많아도 평소 하루치를 넘기 전에는 과다가 아니다', () {
    final history = weekdays(20, [6000, 6500, 7000]);
    // 10시까지 평소는 약 1,000보. 오늘 10시까지 4,500보면 같은 시각 기준으로는 과다(차이 3,000보 이상)
    final sameHour = StepRhythm.judge(
      history: history,
      day: friday,
      hour: 10,
      today: 4500,
      params: const RhythmParams(name: '기존 방식', highAgainstFullDay: false),
    );
    final fullDay = StepRhythm.judge(
      history: history,
      day: friday,
      hour: 10,
      today: 4500,
      params: params,
    );
    expect(sameHour.kind, RhythmKind.high);
    expect(fullDay.kind, RhythmKind.normal);
  });

  test('부족 경계: 오늘 누적이 경계 이상이면 그날은 부족이 될 수 없다', () {
    final j = StepRhythm.judge(
      history: weekdays(20, [3000, 3500, 4000]),
      day: friday,
      hour: 19,
      today: 3300,
      params: const RhythmParams(name: '부족 500', lowMinDiff: 500),
    );
    expect(j.kind, RhythmKind.normal);
    expect(j.lowBoundary, lessThan(3300));
  });

  test('기준 = max(최소 차이, 평소 × 비율)', () {
    const p = RhythmParams(name: 'x', lowMinDiff: 500, lowMinRatio: 0.1);
    expect(p.lowThreshold(3000), 500);
    expect(p.lowThreshold(8000), 800);
  });

  test('주말은 주말끼리만 비교한다', () {
    final history = weekdays(20, [20000]);
    final saturday = DateTime(2026, 11, 7);
    final j = StepRhythm.judge(
      history: history,
      day: saturday,
      hour: 20,
      today: 1000,
      params: params,
    );
    expect(j.kind, RhythmKind.notEnoughData);
  });

  test('되짚기: 평소와 같은 날은 울리지 않고, 많이 걸은 날은 과다가 처음 확인된 시각을 준다', () {
    final days = weekdays(21, [6000, 6500, 7000]);
    final last = days.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    days[last] = spread(14000);
    final result = StepRhythm.backtest(days, params);
    final lastDay = result.last;
    expect(lastDay.day, last);
    expect(lastDay.enoughData, isTrue);
    expect(lastDay.highHour, isNotNull);
    expect(
      result
          .where((d) => d.enoughData && d.day != last)
          .every((d) => d.highHour == null && !d.low),
      isTrue,
    );
  });
}
