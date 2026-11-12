import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'calendar.dart';

const _pixelsPerMinute = 5.0;
const _timeWidth = 61.0;
const _minLaneWidth = 92.0;
const _topInset = 12.0;
const _lineMinutes = 30;

class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.day,
    required this.data,
    required this.onSlot,
    required this.onEvent,
  });

  final DateTime day;
  final CalendarDay data;
  final ValueChanged<DateTime> onSlot;
  final ValueChanged<CalendarEvent> onEvent;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  late final ScrollController _vertical;
  final _horizontal = ScrollController();
  late List<EventPlacement> _placements;

  @override
  void initState() {
    super.initState();
    _placements = placeEvents(widget.data.events, widget.day);
    final now = DateTime.now();
    final anchor = dateOnly(now) == widget.day
        ? now.difference(widget.day).inMinutes - 30
        : _placements.isEmpty
        ? 8 * 60
        : _placements.first.start.floor() - 30;
    _vertical = ScrollController(
      initialScrollOffset: math.max(0, anchor) * _pixelsPerMinute,
    );
  }

  @override
  void didUpdateWidget(Timeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _placements = placeEvents(widget.data.events, widget.day);
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Color _eventColor(CalendarEvent event) =>
      Color(event.color ?? widget.data.calendarFor(event).color).withAlpha(255);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final minutes = dayMinutes(widget.day);
    final allDay = widget.data.events.where((event) => event.allDay).toList();
    final laneCount = _placements.fold(
      1,
      (count, event) => math.max(count, event.laneCount),
    );
    final height = _topInset + minutes * _pixelsPerMinute;
    return Column(
      children: [
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('Cały dzień', style: theme.textTheme.labelSmall),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final event in allDay)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              avatar: Icon(
                                Icons.circle,
                                size: 9,
                                color: _eventColor(event),
                              ),
                              label: Text(event.label),
                              onPressed: () => widget.onEvent(event),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final available = math.max(0.0, viewport.maxWidth - _timeWidth);
              final width = math.max(available, laneCount * _minLaneWidth);
              return Scrollbar(
                controller: _vertical,
                child: SingleChildScrollView(
                  controller: _vertical,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _timeWidth,
                          height: height,
                          child: Stack(
                            children: [
                              for (
                                var offset = 0;
                                offset < minutes;
                                offset += _lineMinutes
                              )
                                Positioned(
                                  top:
                                      _topInset + offset * _pixelsPerMinute - 8,
                                  right: 8,
                                  child: Text(
                                    clock(
                                      widget.day.add(Duration(minutes: offset)),
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            physics: width > available
                                ? null
                                : const NeverScrollableScrollPhysics(),
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (details) {
                                        final offset =
                                            (details.localPosition.dy -
                                                _topInset) /
                                            _pixelsPerMinute;
                                        final slot = slotAt(widget.day, offset);
                                        widget.onSlot(
                                          widget.day.add(
                                            Duration(minutes: slot),
                                          ),
                                        );
                                      },
                                      child: CustomPaint(
                                        painter: _Grid(
                                          minutes,
                                          colors.outlineVariant,
                                          colors.surfaceContainerLow,
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final entry in _placements)
                                    _buildEvent(
                                      entry,
                                      width,
                                      available,
                                      colors,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEvent(
    EventPlacement placement,
    double width,
    double available,
    ColorScheme colors,
  ) {
    final event = placement.event;
    final span = math.min(
      width,
      math.max(available, placement.laneCount * _minLaneWidth),
    );
    final laneWidth = span / placement.laneCount;
    final accent = _eventColor(event);
    final fill = Color.alphaBlend(accent.withAlpha(42), colors.surface);
    return Positioned(
      left: placement.lane * laneWidth + 2,
      top: _topInset + placement.start * _pixelsPerMinute + 1,
      width: laneWidth - 4,
      height: (placement.end - placement.start) * _pixelsPerMinute - 2,
      child: Semantics(
        button: true,
        label: '${event.label}, ${clock(event.start)}–${clock(event.end)}',
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(5),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onEvent(event),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(width: 3, color: accent)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: LayoutBuilder(
                  builder: (context, bounds) => ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            event.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (bounds.maxHeight >= 46)
                          Text(
                            '${clock(event.start)}–${clock(event.end)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grid extends CustomPainter {
  _Grid(this.minutes, this.line, this.background);

  final int minutes;
  final Color line;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, _topInset, size.width, size.height - _topInset),
      Paint()..color = background,
    );
    final paint = Paint()..color = line;
    for (var offset = 0; offset <= minutes; offset += _lineMinutes) {
      final y = _topInset + offset * _pixelsPerMinute;
      paint.strokeWidth = offset % 60 == 0 ? 1 : .5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Grid oldDelegate) =>
      oldDelegate.minutes != minutes ||
      oldDelegate.line != line ||
      oldDelegate.background != background;
}
