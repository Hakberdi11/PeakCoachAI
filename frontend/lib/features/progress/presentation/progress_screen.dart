import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/progress_models.dart';
import '../data/progress_repository.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(progressSummaryProvider);
    final historyAsync = ref.watch(progressHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Progress', style: AppTextStyles.title)),
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryAccent),
          ),
          error: (error, _) => Center(
            child: Text(
              'Could not load progress: $error',
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(label: 'Current Streak', value: '${summary.currentStreak}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(label: 'Longest Streak', value: '${summary.longestStreak}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(label: 'Total Workouts', value: '${summary.totalWorkouts}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      label: 'Total Volume',
                      value: '${summary.totalVolume.toStringAsFixed(0)} kg',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Volume Over Time', style: AppTextStyles.title),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: historyAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryAccent),
                  ),
                  error: (error, _) => Text(
                    'Could not load history: $error',
                    style: AppTextStyles.body.copyWith(color: AppColors.error),
                  ),
                  data: (history) => history.isEmpty
                      ? Center(
                          child: Text('No workouts logged yet.', style: AppTextStyles.body),
                        )
                      : _VolumeChart(history: history),
                ),
              ),
              const SizedBox(height: 24),
              Text('Personal Records', style: AppTextStyles.title),
              const SizedBox(height: 12),
              if (summary.personalRecords.isEmpty)
                Text('No personal records yet.', style: AppTextStyles.body)
              else
                ...summary.personalRecords.map(
                  (pr) => Card(
                    color: AppColors.surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(pr.exerciseName, style: AppTextStyles.body),
                      trailing: Text(
                        '${pr.weight.toStringAsFixed(1)}kg x ${pr.reps}',
                        style: AppTextStyles.label,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTextStyles.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.label),
          ],
        ),
      ),
    );
  }
}

class _VolumeChart extends StatelessWidget {
  const _VolumeChart({required this.history});

  final List<SessionVolumePoint> history;

  @override
  Widget build(BuildContext context) {
    final maxVolume = history.map((h) => h.volume).reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxVolume * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: [
          for (var i = 0; i < history.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: history[i].volume,
                  color: AppColors.primaryAccent,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
