import 'package:flutter/material.dart';

import 'package:caddymoney/l10n/app_localizations.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/theme.dart';

/// A compact date-range control offering quick presets (Day/Week/Month)
/// plus a custom range picker (Filter).
///
/// Designed to be used above transaction lists (user + merchant) to filter items
/// within the selected range.
class TransactionsDateRangeBar extends StatefulWidget {
  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onRangeChanged;
  final VoidCallback onOpenFilter;

  const TransactionsDateRangeBar({super.key, required this.range, required this.onRangeChanged, required this.onOpenFilter});

  static DateTimeRange presetDay({DateTime? now}) {
    final n = (now ?? DateTime.now());
    final start = DateTime(n.year, n.month, n.day);
    final end = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  /// Rolling 7-day window ending today (inclusive).
  static DateTimeRange presetWeek({DateTime? now}) {
    final n = (now ?? DateTime.now());
    final todayStart = DateTime(n.year, n.month, n.day);
    final start = todayStart.subtract(const Duration(days: 6));
    final end = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  /// Rolling 30-day window ending today (inclusive).
  static DateTimeRange presetMonth({DateTime? now}) {
    final n = (now ?? DateTime.now());
    final todayStart = DateTime(n.year, n.month, n.day);
    final start = todayStart.subtract(const Duration(days: 29));
    final end = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  @override
  State<TransactionsDateRangeBar> createState() => _TransactionsDateRangeBarState();
}

class _TransactionsDateRangeBarState extends State<TransactionsDateRangeBar> {
  bool _pressedDay = false;
  bool _pressedWeek = false;
  bool _pressedMonth = false;
  bool _pressedFilter = false;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    final preset = _selectedPreset(widget.range);
    final label = _formatRange(
      widget.range,
      todayLabel: l10n?.today ?? 'Today',
    );

    final surface = cs.surface;
    final border = cs.outlineVariant.withValues(alpha: 0.28);
    final shadow = cs.shadow.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.26 : 0.10);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 26, spreadRadius: -10, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RangeHeaderRow(
            label: label,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm + 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PresetCardButton(
                            label: l10n?.day ?? 'Day',
                            icon: Icons.today,
                            selected: preset == _RangePreset.day,
                            pressed: _pressedDay,
                            onPressedState: (v) => setState(() => _pressedDay = v),
                            onTap: () => widget.onRangeChanged(TransactionsDateRangeBar.presetDay()),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _PresetCardButton(
                            label: l10n?.week ?? 'Week',
                            icon: Icons.date_range,
                            selected: preset == _RangePreset.week,
                            pressed: _pressedWeek,
                            onPressedState: (v) => setState(() => _pressedWeek = v),
                            onTap: () => widget.onRangeChanged(TransactionsDateRangeBar.presetWeek()),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _PresetCardButton(
                            label: l10n?.month ?? 'Month',
                            icon: Icons.calendar_month,
                            selected: preset == _RangePreset.month,
                            pressed: _pressedMonth,
                            onPressedState: (v) => setState(() => _pressedMonth = v),
                            onTap: () => widget.onRangeChanged(TransactionsDateRangeBar.presetMonth()),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _PresetCardButton(
                            label: l10n?.filter ?? 'Filter',
                            icon: Icons.tune,
                            selected: preset == _RangePreset.custom,
                            pressed: _pressedFilter,
                            onPressedState: (v) => setState(() => _pressedFilter = v),
                            onTap: widget.onOpenFilter,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static _RangePreset _selectedPreset(DateTimeRange r) {
    bool same(DateTimeRange a, DateTimeRange b) => a.start.toLocal() == b.start.toLocal() && a.end.toLocal() == b.end.toLocal();
    if (same(r, TransactionsDateRangeBar.presetDay())) return _RangePreset.day;
    if (same(r, TransactionsDateRangeBar.presetWeek())) return _RangePreset.week;
    if (same(r, TransactionsDateRangeBar.presetMonth())) return _RangePreset.month;
    return _RangePreset.custom;
  }

  static String _formatRange(DateTimeRange r, {required String todayLabel}) {
    final s = r.start.toLocal();
    final e = r.end.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final sText = '${two(s.day)}/${two(s.month)}/${s.year}';
    final eText = '${two(e.day)}/${two(e.month)}/${e.year}';
    if (sText == eText) return '$todayLabel • $sText';
    return '$sText  →  $eText';
  }
}

class _RangeHeaderRow extends StatefulWidget {
  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  const _RangeHeaderRow({required this.label, required this.expanded, required this.onToggle});

  @override
  State<_RangeHeaderRow> createState() => _RangeHeaderRowState();
}

class _RangeHeaderRowState extends State<_RangeHeaderRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final border = cs.outlineVariant.withValues(alpha: 0.20);
    final bg = cs.surfaceContainerHighest.withValues(alpha: 0.10);
    final fg = cs.onSurface;

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.992 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 6, vertical: AppSpacing.sm + 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: border)),
            child: Row(
              children: [
                Icon(Icons.event, size: 18, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.label,
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  turns: widget.expanded ? 0.5 : 0,
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


enum _RangePreset { day, week, month, custom }

class _PresetCardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool pressed;
  final ValueChanged<bool> onPressedState;
  final VoidCallback onTap;

  const _PresetCardButton({required this.label, required this.icon, required this.selected, required this.pressed, required this.onPressedState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final border = cs.outlineVariant.withValues(alpha: 0.22);
    final baseBg = cs.surfaceContainerHighest.withValues(alpha: 0.18);
    final shadow = cs.shadow.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.06);
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;

    return Listener(
      onPointerDown: (_) => onPressedState(true),
      onPointerUp: (_) => onPressedState(false),
      onPointerCancel: (_) => onPressedState(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: pressed ? 0.985 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? null : baseBg,
              gradient: selected
                  ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.transactionFilterSelectedGradient)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: border),
              boxShadow: selected
                  ? [BoxShadow(color: shadow, blurRadius: 18, spreadRadius: -10, offset: const Offset(0, 10))]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
