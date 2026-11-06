import 'dart:math';

/// 걸음 리듬 판정(S8). 순수 Dart라 기기 없이 테스트한다.
///
/// 평소 범위: 같은 요일 종류(평일/주말)의 지난 며칠 동안 "같은 시각까지의 누적 걸음" 분포.
/// 활동 과다: 상위 [RhythmParams.percentile] 초과 그리고 평소(중앙값)보다 기준 이상 많음.
/// 활동 부족: 하위 [RhythmParams.percentile] 미만 그리고 평소보다 기준 이상 적음.
/// 기준 = max(최소 걸음 차이, 평소 × 비율). 과다와 부족을 따로 둔다(2026-11-06 검토 중).
class RhythmParams {
  const RhythmParams({
    required this.name,
    this.highMinDiff = 3000,
    this.highMinRatio = 0,
    this.lowMinDiff = 3000,
    this.lowMinRatio = 0,
    this.percentile = 0.10,
    this.minDaySteps = 500,
    this.minWeekdaySamples = 10,
    this.minWeekendSamples = 6,
    this.weekdayWeeks = 4,
    this.weekendWeeks = 8,
    this.lowJudgeHour = 19,
    this.firstSendHour = 8,
    this.lastSendHour = 21,
    this.highAgainstFullDay = true,
  });

  final String name;
  final int highMinDiff;
  final double highMinRatio;
  final int lowMinDiff;
  final double lowMinRatio;
  final double percentile;

  /// 하루 합계가 이보다 적은 날은 평소 범위에서 뺀다(휴대폰을 안 들고 다닌 날).
  final int minDaySteps;
  final int minWeekdaySamples;
  final int minWeekendSamples;
  final int weekdayWeeks;
  final int weekendWeeks;

  /// 활동 부족은 이 시각까지의 누적으로 판정한다(19:30 발송 직전).
  final int lowJudgeHour;

  /// 조용한 시간(21:00~08:00)에는 과다 판정을 하지 않는다.
  final int firstSendHour;
  final int lastSendHour;

  /// 활동 과다를 평소 "하루 전체" 합계 분포와 비교한다(E 방식, 2026-11-06 결정).
  /// false면 평소 "같은 시각까지" 누적 분포와 비교한다(기존 방식, 하루에 여러 번 판정하면 과다가 지나치게 잦음).
  final bool highAgainstFullDay;

  int highThreshold(double usual) =>
      max(highMinDiff, (usual * highMinRatio).round());
  int lowThreshold(double usual) =>
      max(lowMinDiff, (usual * lowMinRatio).round());
}

enum RhythmKind { high, low, normal, notEnoughData }

/// 한 시각의 판정과 근거.
class RhythmJudgement {
  const RhythmJudgement({
    required this.kind,
    required this.today,
    this.usual,
    this.lower,
    this.upper,
    this.highUsual,
    this.highUpper,
    this.lowBoundary,
    this.samples = 0,
  });

  final RhythmKind kind;
  final int today;

  /// 같은 시각까지 누적의 평소(중앙값), 하위/상위 경계.
  final double? usual;
  final double? lower;
  final double? upper;

  /// 과다 비교에 쓴 값(E 방식이면 하루 전체 합계의 평소와 상위 경계).
  final double? highUsual;
  final double? highUpper;

  /// 오늘 누적이 이 값 이상이면 그날은 활동 부족이 될 수 없다(19:30 부족 예약 취소 기준).
  final double? lowBoundary;
  final int samples;
}

/// 하루치 1시간 단위 걸음(00시~23시, 24칸). 날짜는 그날 00:00(지역 시간).
typedef HourlyDays = Map<DateTime, List<int>>;

class StepRhythm {
  StepRhythm._();

  static bool isWeekend(DateTime day) =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  /// [hour]시 정각까지의 누적(0..hour-1칸의 합).
  static int cumulativeUntil(List<int> hours, int hour) =>
      hours.take(hour.clamp(0, 24)).fold(0, (a, b) => a + b);

  /// 선형 보간 백분위(정렬된 값, q는 0~1).
  static double percentile(List<num> sorted, double q) {
    if (sorted.length == 1) return sorted.first.toDouble();
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  /// [day]의 [hour]시 정각까지 누적 [today]를 [history]의 평소 범위와 비교한다.
  static RhythmJudgement judge({
    required HourlyDays history,
    required DateTime day,
    required int hour,
    required int today,
    required RhythmParams params,
    bool lowOnly = false,
    bool highOnly = false,
  }) {
    final sameHour = _baseline(
      history,
      day,
      params,
      (h) => cumulativeUntil(h, hour),
    );
    final need = isWeekend(day)
        ? params.minWeekendSamples
        : params.minWeekdaySamples;
    if (sameHour.length < need) {
      return RhythmJudgement(
        kind: RhythmKind.notEnoughData,
        today: today,
        samples: sameHour.length,
      );
    }
    final fullDay = params.highAgainstFullDay
        ? _baseline(history, day, params, (h) => cumulativeUntil(h, 24))
        : sameHour;
    final usual = percentile(sameHour, 0.5);
    final lower = percentile(sameHour, params.percentile);
    final upper = percentile(sameHour, 1 - params.percentile);
    final highUsual = percentile(fullDay, 0.5);
    final highUpper = percentile(fullDay, 1 - params.percentile);
    final lowBoundary = min(lower, usual - params.lowThreshold(usual));
    var kind = RhythmKind.normal;
    if (!lowOnly &&
        today > highUpper &&
        today - highUsual >= params.highThreshold(highUsual)) {
      kind = RhythmKind.high;
    } else if (!highOnly && today < lowBoundary) {
      kind = RhythmKind.low;
    }
    return RhythmJudgement(
      kind: kind,
      today: today,
      usual: usual,
      lower: lower,
      upper: upper,
      highUsual: highUsual,
      highUpper: highUpper,
      lowBoundary: lowBoundary,
      samples: sameHour.length,
    );
  }

  /// 같은 종류의 날(평일/주말)에서 [value]로 꺼낸 값을 정렬해 돌려준다.
  static List<int> _baseline(
    HourlyDays history,
    DateTime day,
    RhythmParams params,
    int Function(List<int> hours) value,
  ) {
    final weekend = isWeekend(day);
    final windowDays =
        (weekend ? params.weekendWeeks : params.weekdayWeeks) * 7;
    final from = day.subtract(Duration(days: windowDays));
    final values = <int>[
      for (final MapEntry(key: d, value: hours) in history.entries)
        if (d.isBefore(day) &&
            !d.isBefore(from) &&
            isWeekend(d) == weekend &&
            cumulativeUntil(hours, 24) >= params.minDaySteps)
          value(hours),
    ]..sort();
    return values;
  }

  /// 지난 날짜마다 "그날 알림이 울렸을까"를 다시 계산한다.
  /// 과다는 발송 가능 시각(08~21시) 가운데 처음 기준을 넘은 시각, 부족은 [RhythmParams.lowJudgeHour] 시각으로 본다.
  static List<RhythmBacktestDay> backtest(
    HourlyDays days,
    RhythmParams params,
  ) {
    final sorted = days.keys.toList()..sort();
    return [for (final day in sorted) _backtestDay(days, day, params)];
  }

  static RhythmBacktestDay _backtestDay(
    HourlyDays days,
    DateTime day,
    RhythmParams params,
  ) {
    final hours = days[day]!;
    int? highHour;
    var enough = false;
    for (var h = params.firstSendHour; h <= params.lastSendHour; h++) {
      final j = judge(
        history: days,
        day: day,
        hour: h,
        today: cumulativeUntil(hours, h),
        params: params,
        highOnly: true,
      );
      if (j.kind == RhythmKind.notEnoughData) break;
      enough = true;
      if (j.kind == RhythmKind.high) {
        highHour = h;
        break;
      }
    }
    final low = judge(
      history: days,
      day: day,
      hour: params.lowJudgeHour,
      today: cumulativeUntil(hours, params.lowJudgeHour),
      params: params,
      lowOnly: true,
    );
    return RhythmBacktestDay(
      day: day,
      total: hours.fold(0, (a, b) => a + b),
      enoughData: enough && low.kind != RhythmKind.notEnoughData,
      highHour: highHour,
      low: low.kind == RhythmKind.low,
    );
  }
}

class RhythmBacktestDay {
  const RhythmBacktestDay({
    required this.day,
    required this.total,
    required this.enoughData,
    required this.highHour,
    required this.low,
  });

  final DateTime day;
  final int total;
  final bool enoughData;

  /// 활동 과다가 처음 확인된 시각(없으면 null).
  final int? highHour;
  final bool low;
}
