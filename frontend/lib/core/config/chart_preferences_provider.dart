import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:malvifactor/features/analytics/presentation/widgets/macro_factor_chart_widgets.dart';

enum PersistedChartType {
  weightTrend(
    periodKey: 'chart_period_weight_trend',
    scaleKey: 'chart_scale_weight_trend',
  ),
  tdee(
    periodKey: 'chart_period_tdee',
    scaleKey: 'chart_scale_tdee',
  ),
  bodyFat(
    periodKey: 'chart_period_body_fat',
    scaleKey: 'chart_scale_body_fat',
  ),
  goalProgress(
    periodKey: 'chart_period_goal',
    scaleKey: null,
  );

  const PersistedChartType({
    required this.periodKey,
    required this.scaleKey,
  });

  final String periodKey;
  final String? scaleKey;
}

class ChartPreferenceState {
  const ChartPreferenceState({
    required this.range,
    required this.expandedScale,
  });

  final AnalyticsRange range;
  final bool expandedScale;

  ChartPreferenceState copyWith({
    AnalyticsRange? range,
    bool? expandedScale,
  }) {
    return ChartPreferenceState(
      range: range ?? this.range,
      expandedScale: expandedScale ?? this.expandedScale,
    );
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences must be initialized in main()'),
);

class ChartPreferencesNotifier extends StateNotifier<ChartPreferenceState> {
  ChartPreferencesNotifier(this._prefs, this._chartType)
      : super(_loadInitial(_prefs, _chartType));

  final SharedPreferences _prefs;
  final PersistedChartType _chartType;

  static ChartPreferenceState _loadInitial(
    SharedPreferences prefs,
    PersistedChartType type,
  ) {
    final savedPeriod = prefs.getString(type.periodKey);
    AnalyticsRange range = AnalyticsRange.m1;
    if (savedPeriod != null) {
      for (final r in AnalyticsRange.values) {
        if (r.name == savedPeriod || r.label == savedPeriod) {
          range = r;
          break;
        }
      }
    }
    final expanded = type.scaleKey != null
        ? (prefs.getBool(type.scaleKey!) ?? false)
        : false;
    return ChartPreferenceState(range: range, expandedScale: expanded);
  }

  Future<void> setRange(AnalyticsRange range) async {
    state = state.copyWith(range: range);
    await _prefs.setString(_chartType.periodKey, range.name);
  }

  Future<void> toggleScale() async {
    final next = !state.expandedScale;
    state = state.copyWith(expandedScale: next);
    if (_chartType.scaleKey != null) {
      await _prefs.setBool(_chartType.scaleKey!, next);
    }
  }
}

final chartPreferencesProvider = StateNotifierProvider.family<
    ChartPreferencesNotifier, ChartPreferenceState, PersistedChartType>(
  (ref, type) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ChartPreferencesNotifier(prefs, type);
  },
);
