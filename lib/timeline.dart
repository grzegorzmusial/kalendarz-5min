import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
    required this.onReschedule,
  });

  final DateTime day;
  final CalendarDay data;
  final ValueChanged<DateTime> onSlot;
  final ValueChanged<CalendarEvent> onEvent;
  final Future<bool> Function(CalendarEvent, DateTime, DateTime) onReschedule;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  late final ScrollController _vertical;
  final _horizontal = ScrollController();
  late List<EventPlacement> _placements;
  final _viewportKey = GlobalKey();
  CalendarEvent? _selected;
  CalendarEvent? _preview;
  CalendarEvent? _gestureEvent;
  Offset? _originPointer;
  Offset? _lastPointer;
  double _originScroll = 0;
  String _dragKind = 'move';
  bool _saving = false;
  Timer? _autoScroll;

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
    _autoScroll?.cancel();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Color _eventColor(CalendarEvent event) =>
      Color(event.color ?? widget.data.calendarFor(event).color).withAlpha(255);

  bool _isSelected(CalendarEvent event) =>
      _selected?.id == event.id && _selected?.start == event.start;

  bool _canEdit(CalendarEvent event) =>
      !_saving &&
      !event.allDay &&
      event.canModify &&
      widget.data.calendarFor(event).writable;

  void _startGesture(CalendarEvent event, Offset pointer, String kind) {
    if (!_canEdit(event)) return;
    final base = _isSelected(event) ? _preview ?? event : event;
    setState(() {
      _selected = event;
      _preview = base;
      _gestureEvent = base;
      _originPointer = pointer;
      _lastPointer = pointer;
      _originScroll = _vertical.offset;
      _dragKind = kind;
    });
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || _lastPointer == null || !_vertical.hasClients) return;
      final y = box.globalToLocal(_lastPointer!).dy;
      final speed = y < 40
          ? -12.0
          : y > box.size.height - 40
          ? 12.0
          : 0.0;
      final offset = (_vertical.offset + speed).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      if (offset == _vertical.offset) return;
      _vertical.jumpTo(offset);
      _updatePreview();
    });
  }

  void _moveGesture(Offset pointer) {
    _lastPointer = pointer;
    _updatePreview();
  }

  void _updatePreview() {
    final base = _gestureEvent;
    if (base == null || _originPointer == null || _lastPointer == null) return;
    final delta =
        (_lastPointer!.dy -
            _originPointer!.dy +
            _vertical.offset -
            _originScroll) /
        _pixelsPerMinute;
    final startOffset =
        base.start.difference(widget.day).inMilliseconds / 60000;
    final endOffset = base.end.difference(widget.day).inMilliseconds / 60000;
    final minutes = dayMinutes(widget.day);
    int snap(double value) => (value / slotMinutes).round() * slotMinutes;
    DateTime start = base.start;
    DateTime end = base.end;
    if (_dragKind == 'start') {
      final latest = math.min(
        minutes - slotMinutes,
        endOffset.floor() - slotMinutes,
      );
      final offset = snap(startOffset + delta)
          .clamp(math.min(0, latest), latest);
      start = widget.day.add(Duration(minutes: offset.toInt()));
    } else if (_dragKind == 'end') {
      final earliest = math.max(slotMinutes, startOffset.ceil() + slotMinutes);
      final offset = snap(endOffset + delta)
          .clamp(earliest, math.max(earliest, minutes));
      end = widget.day.add(Duration(minutes: offset.toInt()));
    } else {
      final target = snap(startOffset + delta).toDouble();
      final shift = (target - startOffset).clamp(
        slotMinutes - endOffset,
        minutes - slotMinutes - startOffset,
      );
      final duration = Duration(milliseconds: (shift * 60000).round());
      start = base.start.add(duration);
      end = base.end.add(duration);
    }
    setState(() => _preview = base.withTimes(start, end));
  }

  void _cancelGesture() {
    _autoScroll?.cancel();
    setState(() {
      _gestureEvent = null;
      _preview = null;
    });
  }

  Future<void> _finishGesture() async {
    _autoScroll?.cancel();
    final event = _selected;
    final preview = _preview;
    _gestureEvent = null;
    if (event == null ||
        preview == null ||
        (event.start == preview.start && event.end == preview.end)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onReschedule(event, preview.start, preview.end);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _selected = null;
          _preview = null;
        });
      }
    }
  }

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
            key: _viewportKey,
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
                                        if (_saving) return;
                                        if (_selected != null) {
                                          setState(() {
                                            _selected = null;
                                            _preview = null;
                                          });
                                          return;
                                        }
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
                                  for (final entry in _placements.where(
                                    (entry) => _isSelected(entry.event),
                                  ))
                                    ..._handles(
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
    final original = placement.event;
    final event = _isSelected(original) ? _preview ?? original : original;
    final start = event.start.difference(widget.day).inMilliseconds / 60000;
    final end = event.end.difference(widget.day).inMilliseconds / 60000;
    final visibleStart = start.clamp(
      0.0,
      dayMinutes(widget.day) - slotMinutes.toDouble(),
    );
    final visibleEnd = end.clamp(
      visibleStart + slotMinutes,
      dayMinutes(widget.day).toDouble(),
    );
    final span = math.min(
      width,
      math.max(available, placement.laneCount * _minLaneWidth),
    );
    final laneWidth = span / placement.laneCount;
    final accent = _eventColor(event);
    final fill = Color.alphaBlend(accent.withAlpha(42), colors.surface);
    return Positioned(
      key: ValueKey('${original.id}:${original.start.millisecondsSinceEpoch}'),
      left: placement.lane * laneWidth + 2,
      top: _topInset + visibleStart * _pixelsPerMinute + 1,
      width: laneWidth - 4,
      height: (visibleEnd - visibleStart) * _pixelsPerMinute - 2,
      child: Semantics(
        button: true,
        label: '${event.label}, ${clock(event.start)}–${clock(event.end)}',
        child: GestureDetector(
          onLongPressStart: _canEdit(original)
              ? (details) =>
                    _startGesture(original, details.globalPosition, 'move')
              : null,
          onLongPressMoveUpdate: _canEdit(original)
              ? (details) => _moveGesture(details.globalPosition)
              : null,
          onLongPressEnd: _canEdit(original) ? (_) => _finishGesture() : null,
          onLongPressCancel: _canEdit(original) ? _cancelGesture : null,
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _saving ? null : () => widget.onEvent(original),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: _isSelected(original)
                      ? Border.all(width: 2, color: colors.primary)
                      : Border(left: BorderSide(width: 3, color: accent)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
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
      ),
    );
  }

  List<Widget> _handles(
    EventPlacement entry,
    double width,
    double available,
    ColorScheme colors,
  ) {
    final event = _preview ?? entry.event;
    final laneWidth =
        math.min(width, math.max(available, entry.laneCount * _minLaneWidth)) /
        entry.laneCount;
    final start = event.start.difference(widget.day).inMilliseconds / 60000;
    final end = event.end.difference(widget.day).inMilliseconds / 60000;
    final minutes = dayMinutes(widget.day);
    Widget handle(String kind, double offset, String label) => Positioned(
      key: ValueKey('handle-$kind'),
      left: entry.lane * laneWidth + laneWidth / 2 - 20,
      top: _topInset + offset * _pixelsPerMinute - 12,
      width: 40,
      height: 24,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _saving
              ? null
              : (details) =>
                    _startGesture(entry.event, details.globalPosition, kind),
          onVerticalDragUpdate: _saving
              ? null
              : (details) => _moveGesture(details.globalPosition),
          onVerticalDragEnd: _saving ? null : (_) => _finishGesture(),
          onVerticalDragCancel: _saving ? null : _cancelGesture,
          child: Center(
            child: Container(
              width: 28,
              height: 9,
              decoration: BoxDecoration(
                color: colors.primary,
                border: Border.all(color: colors.surface, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
    return [
      Positioned(
        left: entry.lane * laneWidth + 3,
        top: math.max(
          0,
          _topInset + math.max(0, start) * _pixelsPerMinute - 32,
        ),
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: colors.primary,
            child: Text(
              '${clock(event.start)}–${clock(event.end)}',
              style: TextStyle(color: colors.onPrimary, fontSize: 12),
            ),
          ),
        ),
      ),
      if (start >= 0 && start < minutes)
        handle('start', start, 'Zmień godzinę rozpoczęcia'),
      if (end > 0 && end <= minutes)
        handle('end', end, 'Zmień godzinę zakończenia'),
    ];
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
