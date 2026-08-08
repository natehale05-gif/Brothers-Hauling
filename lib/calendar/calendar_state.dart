import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/job.dart';
import 'date_math.dart';
import 'event.dart';

/// The five ways Apple Calendar shows the same days.
enum CalView {
  day('Day'),
  week('Week'),
  month('Month'),
  year('Year'),
  list('List');

  const CalView(this.label);

  final String label;
}

/// What the calendar is looking at.
///
/// Deliberately separate from the domain state: which day is on screen and
/// which view is chosen are facts about this device at this moment. Nothing
/// here is ever queued for dispatch, and nothing here belongs on a server.
class CalendarState extends ChangeNotifier {
  CalendarState({
    DateTime Function()? now,
    CalView view = CalView.month,
    Duration tick = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _view = view {
    _focused = dayOf(_now());
    _selected = _focused;
    // The now-line has to move on its own or it is a lie within the minute.
    if (tick > Duration.zero) {
      _ticker = Timer.periodic(tick, (_) => notifyListeners());
    }
  }

  final DateTime Function() _now;
  Timer? _ticker;

  CalView _view;
  late DateTime _focused;
  late DateTime _selected;
  String? _openEventId;
  final Set<WorkCalendar> _hidden = {};

  DateTime get now => _now();
  DateTime get today => dayOf(_now());

  CalView get view => _view;

  /// The period on screen — the month a month view is showing, the day a day
  /// view is showing.
  DateTime get focused => _focused;

  /// The day the user last picked out. A month view highlights it; moving to
  /// the day view opens it.
  DateTime get selected => _selected;

  String? get openEventId => _openEventId;

  /// Which colour sets are switched off.
  Set<WorkCalendar> get hidden => Set.unmodifiable(_hidden);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void setView(CalView view) {
    if (view == _view) return;
    _view = view;
    notifyListeners();
  }

  /// Moves the calendar to [day], and selects it.
  void focus(DateTime day) {
    final target = dayOf(day);
    if (sameDay(target, _focused) && sameDay(target, _selected)) return;
    _focused = target;
    _selected = target;
    notifyListeners();
  }

  /// Picks a day without leaving the period on screen — tapping a cell in the
  /// month grid, where the grid must not jump underneath the finger.
  void select(DateTime day) {
    final target = dayOf(day);
    if (sameDay(target, _selected)) return;
    _selected = target;
    notifyListeners();
  }

  void goToToday() => focus(today);

  /// Steps one period in the direction the current view moves.
  ///
  /// A month view pages by months and a day view by days: "next" has to mean
  /// what is on screen, or the arrow lies.
  void step(int by) {
    focus(switch (_view) {
      CalView.day || CalView.list => _focused.add(Duration(days: by)),
      CalView.week => _focused.add(Duration(days: 7 * by)),
      CalView.month => addMonths(_focused, by),
      CalView.year => DateTime(_focused.year + by, _focused.month, 1),
    });
  }

  void openEvent(String? id) {
    if (id == _openEventId) return;
    _openEventId = id;
    notifyListeners();
  }

  void closeEvent() => openEvent(null);

  /// Switches a colour set on or off.
  ///
  /// Hiding is a view, not a filter on the data: the jobs are all still there,
  /// they are simply not drawn. Nothing here changes what anybody can do.
  void toggleCalendar(WorkCalendar calendar) {
    if (!_hidden.remove(calendar)) _hidden.add(calendar);
    notifyListeners();
  }

  void showAllCalendars() {
    if (_hidden.isEmpty) return;
    _hidden.clear();
    notifyListeners();
  }

  bool isVisible(WorkCalendar calendar) => !_hidden.contains(calendar);

  /// Every job with a day on it, as events, minus the hidden colour sets.
  List<CalendarEvent> visible(Iterable<Job> jobs) => [
    for (final event in eventsFrom(jobs))
      if (isVisible(event.calendar)) event,
  ];

  /// The title over the current view — "August 2026", "2026", "Thursday".
  String get title => switch (_view) {
    CalView.year => '${_focused.year}',
    CalView.month => '${monthName(_focused)} ${_focused.year}',
    CalView.week => _weekTitle(),
    CalView.day || CalView.list => '${monthName(_focused)} ${_focused.year}',
  };

  String _weekTitle() {
    final days = weekDays(_focused);
    final from = days.first;
    final to = days.last;
    if (from.month == to.month) return '${monthName(from)} ${from.year}';
    // A week that straddles a month says so, rather than picking a side.
    return '${monthShort(from)} – ${monthShort(to)} ${to.year}';
  }
}

/// Hands the calendar state down the tree.
class CalendarScope extends InheritedNotifier<CalendarState> {
  const CalendarScope({
    super.key,
    required CalendarState state,
    required super.child,
  }) : super(notifier: state);

  static CalendarState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CalendarScope>();
    assert(scope != null, 'No CalendarScope above this widget');
    return scope!.notifier!;
  }

  /// Reads without subscribing — for callbacks that only ever write.
  static CalendarState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CalendarScope>();
    assert(scope != null, 'No CalendarScope above this widget');
    return scope!.notifier!;
  }
}
