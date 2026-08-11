import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'crew_screen.dart';
import 'date_math.dart';
import 'event.dart';
import 'event_editor.dart';
import 'device_sheet.dart';
import 'event_sheet.dart';
import 'logins.dart';
import 'search.dart';
import 'views/day_view.dart';
import 'views/list_view.dart';
import 'views/month_view.dart';
import 'views/week_view.dart';
import 'views/year_view.dart';

/// The calendar, whole.
///
/// One nav bar, one view at a time, a segmented control to change which. The
/// shape is Apple Calendar's: title on the left, actions on the right, Today
/// at the bottom, and the view you were on remembered as you move around.
class CalendarHome extends StatelessWidget {
  const CalendarHome({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final app = AppScope.of(context);
    final events = cal.visible(app.jobs);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
        SingleActivator(LogicalKeyboardKey.keyT): _TodayIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
      },
      child: Actions(
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(
            onInvoke: (i) {
              cal.step(i.by);
              return null;
            },
          ),
          _TodayIntent: CallbackAction<_TodayIntent>(
            onInvoke: (_) {
              cal.goToToday();
              return null;
            },
          ),
          _CloseIntent: CallbackAction<_CloseIntent>(
            onInvoke: (_) {
              cal.closeEvent();
              return null;
            },
          ),
          _NewIntent: CallbackAction<_NewIntent>(
            onInvoke: (_) {
              if (app.canEditJobs) {
                showEventEditor(
                  context,
                  startAt: startOfWorking(cal.selected, cal.now),
                );
              }
              return null;
            },
          ),
          _FindIntent: CallbackAction<_FindIntent>(
            onInvoke: (_) {
              showCalendarSearch(context);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      const CalendarNavBar(),
                      Expanded(child: _Body(events: events)),
                      const ViewSwitcher(),
                    ],
                  ),
                  if (cal.openEventId != null)
                    EventSheet(
                      event: events
                          .where((e) => e.id == cal.openEventId)
                          .firstOrNull,
                    ),
                  const _Toast(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the app says back.
///
/// The state has been saying these all along — a refused price, a job put on
/// the board, a photo filed, a close-out blocked — and until now nothing drew
/// them. An app that answers into the void is worse than one that says
/// nothing, because the silence reads as "that worked".
///
/// Over everything, including an open job sheet, since most of what it has to
/// say is about the button just pressed on one.
class _Toast extends StatelessWidget {
  const _Toast();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final said = AppScope.of(context).toast;
    if (said == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: p.label,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                said,
                textAlign: TextAlign.center,
                style: t.body.copyWith(fontSize: 14, color: p.bg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.by);

  final int by;
}

class _TodayIntent extends Intent {
  const _TodayIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _Body extends StatelessWidget {
  const _Body({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final cal = CalendarScope.of(context);
    return switch (cal.view) {
      CalView.day => DayView(events: events),
      CalView.week => WeekView(events: events),
      CalView.month => MonthView(events: events),
      CalView.year => YearView(events: events),
      CalView.list => ScheduleView(events: events),
    };
  }
}

/// Title, arrows, Today, and the calendars button.
class CalendarNavBar extends StatelessWidget {
  const CalendarNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final onToday = sameDay(cal.focused, cal.today);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(bottom: BorderSide(color: p.separator, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // The arrows are the one control here with a replacement: every
          // view pages by swipe, and the keys do it on a desktop. On a narrow
          // phone — or at the largest text the app allows — they are what
          // gives, rather than the bar running off the side of the screen.
          // Five 44pt targets, a Today button and something left for the
          // title. Scaled, because the Today button grows with the text and
          // the icons do not.
          final needs = 360 * MediaQuery.textScalerOf(context).scale(1);
          final showArrows = box.maxWidth >= needs;
          return _NavRow(showArrows: showArrows, onToday: onToday);
        },
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.showArrows, required this.onToday});

  final bool showArrows;
  final bool onToday;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true,
            button: true,
            label: '${cal.title}. Go to date',
            onTap: () => showGoToDate(context),
            excludeSemantics: true,
            // The title is the date jump, the way tapping the month name is
            // on the real one — no eighth button in a bar this narrow.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showGoToDate(context),
              child: Text(
                cal.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.navTitle.copyWith(fontSize: 20),
              ),
            ),
          ),
        ),
        _BarButton(
          icon: Icons.search_rounded,
          tooltip: 'Search',
          onTap: () => showCalendarSearch(context),
        ),
        if (showArrows)
          _BarButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous',
            onTap: () => cal.step(-1),
          ),
        if (!onToday)
          Semantics(
            button: true,
            label: 'Back to today',
            onTap: cal.goToToday,
            excludeSemantics: true,
            child: TextButton(
              onPressed: cal.goToToday,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: p.accent,
              ),
              child: Text(
                'Today',
                style: t.body.copyWith(fontSize: 15, color: p.accent),
              ),
            ),
          ),
        if (showArrows)
          _BarButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next',
            onTap: () => cal.step(1),
          ),
        _BarButton(
          icon: Icons.tune_rounded,
          tooltip: 'Calendars',
          onTap: () => showCalendarsSheet(context),
        ),
        if (AppScope.of(context).canEditJobs)
          _BarButton(
            icon: Icons.add_rounded,
            tooltip: 'New job',
            // Opens on the day you are looking at, not on today — the
            // whole reason you paged there.
            onTap: () => showEventEditor(
              context,
              startAt: startOfWorking(cal.selected, cal.now),
            ),
          ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      onTap: onTap,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        iconSize: 24,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, color: p.accent),
      ),
    );
  }
}

/// Day / Week / Month / Year / List, as a segmented control.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.separator, width: 0.5)),
      ),
      // Apple's segmented control is a fixed size sitting in the middle of the
      // bar, not a thing that grows to fill a desktop window. On a phone the
      // window is narrower than the cap, so it fills the width as it should.
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minHeight: 34),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: p.fill,
            borderRadius: BorderRadius.circular(9),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              for (final view in CalView.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: cal.view == view,
                    label:
                        '${view.label} view, '
                        '${CalView.values.indexOf(view) + 1} of '
                        '${CalView.values.length}',
                    onTap: () => cal.setView(view),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => cal.setView(view),
                      child: Container(
                        decoration: cal.view == view
                            ? BoxDecoration(
                                color: p.card,
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              )
                            : null,
                        alignment: Alignment.center,
                        child: Text(
                          view.label,
                          style: t.secondary.copyWith(
                            fontSize: 13,
                            color: p.label,
                            fontWeight: cal.view == view
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
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

/// Who is signed in, the way out, and the way to the logins.
class _AccountRow extends StatelessWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final session = app.session;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            session == null
                ? 'Signed in'
                : '${session.username} · ${session.role.label}',
            style: t.bodyStrong.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            app.role?.blurb ?? '',
            style: t.secondary.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (app.canTrackCrew)
                Semantics(
                  button: true,
                  label: 'Crew',
                  onTap: () => showCrew(context),
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: () => showCrew(context),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      'Crew',
                      style: t.body.copyWith(fontSize: 15, color: p.accent),
                    ),
                  ),
                ),
              if (app.canTrackCrew) const SizedBox(width: 16),
              if (app.canManageServer)
                Semantics(
                  button: true,
                  label: 'Logins',
                  onTap: () => showLogins(context),
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: () => showLogins(context),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      'Logins',
                      style: t.body.copyWith(fontSize: 15, color: p.accent),
                    ),
                  ),
                ),
              if (app.canManageServer) const SizedBox(width: 16),
              Semantics(
                button: true,
                label: 'Sign out',
                onTap: () {
                  Navigator.of(context).pop();
                  app.signOut();
                },
                excludeSemantics: true,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    app.signOut();
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    'Sign out',
                    style: t.body.copyWith(fontSize: 15, color: p.accent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the device has been asked to buzz about.
///
/// Here rather than in a settings screen the app does not have, and worth
/// showing at all because a reminder that was refused is indistinguishable
/// from one that simply has not gone off yet.
class _AlertsRow extends StatelessWidget {
  const _AlertsRow();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final set = app.alerts.length;

    final String status;
    if (!app.alertsAllowed) {
      status = 'This device has turned reminders off.';
    } else if (set == 0) {
      status =
          'No reminders set. Add one to a job to be told before it '
          'starts.';
    } else {
      status =
          '$set ${set == 1 ? 'reminder' : 'reminders'} set. The next is '
          '${shortDate(app.alerts.first.at)} at '
          '${clockLabel(app.alerts.first.at)}.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                app.alertsAllowed
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: 18,
                color: app.alertsAllowed ? p.accent : p.secondaryLabel,
              ),
              const SizedBox(width: 8),
              Text('Reminders', style: t.bodyStrong.copyWith(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(status, style: t.secondary.copyWith(fontSize: 13)),
          ),
          if (!app.alertsAllowed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: app.enableAlerts,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  'Turn reminders on',
                  style: t.body.copyWith(fontSize: 15, color: p.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The calendars list — which colour sets are drawn.
Future<void> showCalendarsSheet(BuildContext context) {
  final cal = CalendarScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: CalPalette.of(context).groupedBg,
    showDragHandle: true,
    builder: (_) => CalendarScope(state: cal, child: const _CalendarsSheet()),
  );
}

class _CalendarsSheet extends StatelessWidget {
  const _CalendarsSheet();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return SafeArea(
      // Scrolls, because a bottom sheet is only ever given part of the screen
      // and this one grew a reminders panel. At the largest text the app
      // allows it is taller than the room a short phone has for it.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('Calendars', style: t.navTitle),
            ),
            for (final calendar in WorkCalendar.values)
              Semantics(
                button: true,
                checked: cal.isVisible(calendar),
                label:
                    '${calendar.label}, '
                    '${cal.isVisible(calendar) ? 'shown' : 'hidden'}',
                onTap: () => cal.toggleCalendar(calendar),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => cal.toggleCalendar(calendar),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: cal.isVisible(calendar)
                                ? calendar.colour
                                : Colors.transparent,
                            border: Border.all(
                              color: calendar.colour,
                              width: 2,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: cal.isVisible(calendar)
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(calendar.label, style: t.body)),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton(
                onPressed: cal.showAllCalendars,
                child: Text(
                  'Show all',
                  style: t.body.copyWith(fontSize: 15, color: p.accent),
                ),
              ),
            ),
            const Divider(height: 24),
            const _AlertsRow(),
            const Divider(height: 24),
            const SyncRow(),
            const ServerRow(),
            const Divider(height: 24),
            const _AccountRow(),
          ],
        ),
      ),
    );
  }
}
