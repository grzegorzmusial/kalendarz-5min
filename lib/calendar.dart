import 'dart:math' as math;

import 'package:flutter/services.dart';

const slotMinutes = 5;

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime shiftDay(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

int dayMinutes(DateTime day) => shiftDay(day, 1).difference(day).inMinutes;

int slotAt(DateTime day, double minutes) =>
    ((minutes / slotMinutes).floor() * slotMinutes).clamp(
      0,
      dayMinutes(day) - slotMinutes,
    );

String clock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String slotLabel(DateTime day, DateTime time) {
  if (dayMinutes(day) <= 1440) return clock(time);
  final hour = time.timeZoneOffset.inHours;
  final sign = hour < 0 ? '−' : '+';
  return '${clock(time)} ($sign${hour.abs()})';
}

String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours godz.' : '$hours godz. $remainder min';
}

class GoogleCalendar {
  GoogleCalendar(Map<Object?, Object?> row)
    : id = row['id'] as int,
      name = row['name'] as String,
      account = row['account'] as String,
      color = row['color'] as int,
      writable = row['writable'] as bool;

  final int id;
  final String name;
  final String account;
  final int color;
  final bool writable;

  String get label =>
      name.isEmpty || name == account ? account : '$name · $account';
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.recurring = false,
    this.canModify = true,
    this.color,
    this.taskId,
    this.taskListId,
  });

  factory CalendarEvent.fromRow(Map<Object?, Object?> row) {
    return CalendarEvent(
      id: row['id'] as int,
      calendarId: row['calendarId'] as int,
      title: row['title'] as String,
      start: DateTime.fromMillisecondsSinceEpoch(row['start'] as int),
      end: DateTime.fromMillisecondsSinceEpoch(row['end'] as int),
      allDay: row['allDay'] as bool,
      recurring: row['recurring'] as bool,
      canModify: row['canModify'] as bool,
      color: row['color'] as int?,
    );
  }

  final int id;
  final int calendarId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool recurring;
  final bool canModify;
  final int? color;
  final String? taskId;
  final String? taskListId;
  Object get identity => taskId == null ? (id, start) : (taskListId, taskId);

  CalendarEvent withTimes(DateTime start, DateTime end) => CalendarEvent(
    id: id,
    calendarId: calendarId,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    recurring: recurring,
    canModify: canModify,
    color: color,
    taskId: taskId,
    taskListId: taskListId,
  );

  String get label => title.trim().isEmpty ? 'Bez tytułu' : title;
}

class CalendarDay {
  const CalendarDay(this.calendars, this.events);

  final List<GoogleCalendar> calendars;
  final List<CalendarEvent> events;

  GoogleCalendar calendarFor(CalendarEvent event) =>
      calendars.firstWhere((calendar) => calendar.id == event.calendarId);
}

class CalendarStore {
  static const _channel = MethodChannel('calendar/android');

  void onChange(void Function()? listener) {
    _channel.setMethodCallHandler(
      listener == null
          ? null
          : (call) async {
              if (call.method == 'changed') listener();
            },
    );
  }

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openSettings({bool permissions = false}) =>
      _channel.invokeMethod<void>(permissions ? 'appSettings' : 'settings');

  Future<int?> defaultCalendar() =>
      _channel.invokeMethod<int>('defaultCalendar');

  Future<String> taskClientId() async {
    final configured = await _channel.invokeMethod<String>('taskClientId');
    if (configured != null && configured.trim().isNotEmpty) return configured;
    return const String.fromEnvironment('GOOGLE_TASKS_CLIENT_ID');
  }

  Future<void> setTaskClientId(String clientId) =>
      _channel.invokeMethod<void>('setTaskClientId', {'clientId': clientId});

  Future<({String id, String email})?> taskAccount() async {
    final account = await _channel.invokeMapMethod<String, String>(
      'taskAccount',
    );
    final id = account?['id'];
    final email = account?['email'];
    if (id == null || email == null || id.isEmpty || email.isEmpty) return null;
    return (id: id, email: email);
  }

  Future<void> setTaskAccount(String id, String email) =>
      _channel.invokeMethod<void>('setTaskAccount', {'id': id, 'email': email});

  Future<void> clearTaskAccount() =>
      _channel.invokeMethod<void>('clearTaskAccount');

  Future<void> setDefaultCalendar(int calendarId) => _channel
      .invokeMethod<void>('setDefaultCalendar', {'calendarId': calendarId});

  Future<CalendarDay> readDay(DateTime date) async {
    final result = await _channel.invokeMapMethod<String, List<Object?>>(
      'day',
      {
        'start': date.millisecondsSinceEpoch,
        'end': shiftDay(date, 1).millisecondsSinceEpoch,
        'utcStart': DateTime.utc(
          date.year,
          date.month,
          date.day,
        ).millisecondsSinceEpoch,
        'utcEnd': DateTime.utc(
          date.year,
          date.month,
          date.day + 1,
        ).millisecondsSinceEpoch,
      },
    );
    return CalendarDay(
      result!['calendars']!
          .cast<Map<Object?, Object?>>()
          .map(GoogleCalendar.new)
          .toList(),
      result['events']!
          .cast<Map<Object?, Object?>>()
          .map(CalendarEvent.fromRow)
          .toList(),
    );
  }

  Future<void> save({
    required int calendarId,
    required String title,
    required DateTime start,
    required DateTime end,
    CalendarEvent? event,
  }) => _channel.invokeMethod<void>('save', {
    'calendarId': calendarId,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'id': event?.id,
    'originalStart': event?.start.millisecondsSinceEpoch,
  });
}

class EventPlacement {
  EventPlacement(this.event, this.start, this.end);

  final CalendarEvent event;
  final double start;
  final double end;
  int lane = 0;
  int laneCount = 1;
}

List<EventPlacement> placeEvents(List<CalendarEvent> events, DateTime day) {
  final minutes = dayMinutes(day).toDouble();
  double offset(DateTime time) => time.difference(day).inMilliseconds / 60000;
  final placements =
      events.where((event) => !event.allDay).map((event) {
        final start = offset(event.start).clamp(0.0, minutes - slotMinutes);
        final end = offset(event.end).clamp(start + slotMinutes, minutes);
        return EventPlacement(event, start, end);
      }).toList()..sort((a, b) {
        final startOrder = a.start.compareTo(b.start);
        if (startOrder != 0) return startOrder;
        final endOrder = b.end.compareTo(a.end);
        return endOrder == 0 ? a.event.id.compareTo(b.event.id) : endOrder;
      });

  final laneEnds = <double>[];
  var groupStart = 0;
  var groupEnd = 0.0;
  void finishGroup(int endIndex) {
    for (var index = groupStart; index < endIndex; index++) {
      placements[index].laneCount = laneEnds.length;
    }
  }

  for (var index = 0; index < placements.length; index++) {
    final event = placements[index];
    if (event.start >= groupEnd) {
      finishGroup(index);
      laneEnds.clear();
      groupStart = index;
    }
    groupEnd = math.max(groupEnd, event.end);
    final available = laneEnds.indexWhere((end) => end <= event.start);
    if (available == -1) {
      event.lane = laneEnds.length;
      laneEnds.add(event.end);
    } else {
      event.lane = available;
      laneEnds[available] = event.end;
    }
  }
  finishGroup(placements.length);
  return placements;
}
