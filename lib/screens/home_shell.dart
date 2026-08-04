import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/job.dart';
import '../models/time_entry.dart';
import '../models/role.dart';
import '../services/link_service.dart';
import '../services/location_service.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import '../widgets/primitives.dart';
import '../widgets/route_strip.dart';
import '../widgets/sync_strip.dart';
import '../widgets/theme_toggle.dart';
import 'job_detail.dart';
import 'role_gate.dart';
import 'tabs/day_board.dart';
import 'tabs/dispatch_tabs.dart';
import 'tabs/employee_tabs.dart';
import 'tabs/hours_tab.dart';

/// The signed-in app.
///
/// One layout below [HaulSpace.wideBreakpoint] — bottom tabs, job card takes
/// over the screen. One above — a navigation rail with the job card in a
/// permanent side pane. Same widgets either way; only the chrome differs, which
/// is what keeps a phone, an iPad, and a desktop window on one codebase.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.links});

  final LinkService links;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final state = AppScope.of(context);
    if (state.role == null) return const RoleGate();

    final wide = MediaQuery.sizeOf(context).width >= HaulSpace.wideBreakpoint;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
        // Left/right step the day view. Bound here rather than inside it
        // because this is the focus node that actually has focus; a nested
        // one never gets a look at the key. Guarded by the tab so arrow keys
        // still scroll everywhere else.
        SingleActivator(LogicalKeyboardKey.arrowLeft): _StepDayIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _StepDayIntent(1),
      },
      child: Actions(
        actions: {
          _StepDayIntent: CallbackAction<_StepDayIntent>(
            onInvoke: (intent) {
              if (state.tab == HaulTab.day) state.stepDay(intent.by);
              return null;
            },
          ),
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              if (state.closedJob != null) {
                state.dismissClosedJob();
              } else {
                state.closeJobCard();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: hc.bg,
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      const _TopBar(),
                      // Above the location strip: whether your work has landed
                      // matters more than where you are.
                      const SyncStrip(),
                      if (state.employeeView) const _LocationStrip(),
                      Expanded(
                        child: wide
                            ? _WideBody(links: links)
                            : _NarrowBody(links: links),
                      ),
                      if (!wide) const HaulBottomTabs(),
                    ],
                  ),
                  if (state.toast != null)
                    _Toast(message: state.toast!, raised: !wide),
                  if (state.closedJob != null)
                    _ClosedOverlay(job: state.closedJob!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class _StepDayIntent extends Intent {
  const _StepDayIntent(this.by);

  /// Days to move, signed.
  final int by;
}

/// Phone/handheld: the job card replaces the list.
class _NarrowBody extends StatelessWidget {
  const _NarrowBody({required this.links});

  final LinkService links;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final job = state.openJob;

    if (job != null) {
      return JobDetail(job: job, links: links);
    }
    return const _TabBody();
  }
}

/// Tablet/desktop: rail, list, and a permanent detail pane.
class _WideBody extends StatelessWidget {
  const _WideBody({required this.links});

  final LinkService links;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final state = AppScope.of(context);
    final job = state.openJob;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _NavRail(),
        VerticalDivider(width: 1, color: hc.line),
        Expanded(flex: 3, child: _TabBody(selectedJobId: job?.id)),
        if (job != null) ...[
          VerticalDivider(width: 1, color: hc.line),
          Expanded(
            flex: 4,
            child: JobDetail(job: job, links: links, showCloseButton: false),
          ),
        ],
      ],
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({this.selectedJobId});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final Widget body = switch (state.tab) {
      HaulTab.board => EmployeeBoardTab(selectedJobId: selectedJobId),
      HaulTab.day => DayBoard(selectedJobId: selectedJobId),
      HaulTab.mine => EmployeeMineTab(selectedJobId: selectedJobId),
      HaulTab.jobs => JobsTab(selectedJobId: selectedJobId),
      HaulTab.crew => const CrewTab(),
      HaulTab.hours => const HoursTab(),
      HaulTab.tracking => const TrackingTab(),
      HaulTab.overview => const OverviewTab(),
    };

    // The day view scrolls per day, inside its own pager, so it needs the
    // height rather than being shrink-wrapped by a scroll view that would
    // leave its pages with nothing to fill. Every other tab is a column of
    // content that grows as long as it likes.
    if (state.tab == HaulTab.day) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              // Wider than the reading column: a grid wants the window.
              maxWidth: HaulSpace.maxContentWidth * 1.9,
            ),
            child: body,
          ),
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HaulSpace.maxContentWidth,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final role = state.role!;
    final s = RoleGate.styleFor(role, hc);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(bottom: BorderSide(color: hc.line)),
      ),
      child: Row(
        children: [
          CrewAvatar(initials: state.me.initials),
          const SizedBox(width: 11),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.me.name, style: ht.bodyStrong),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Pill(
                          label: state.asEmployee
                              ? '${role.label} · employee view'
                              : role.label,
                          icon: s.icon,
                          tone: s.tone,
                          semanticLabel: state.asEmployee
                              ? 'Signed in as ${role.label}, currently in the '
                                    'employee view'
                              : 'Signed in as ${role.label}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (role != Role.employee)
            HaulIconButton(
              icon: Icons.visibility_outlined,
              active: state.asEmployee,
              tooltip: state.asEmployee
                  ? 'Back to the ${role.label.toLowerCase()} view'
                  : "See what the crew sees",
              onPressed: state.toggleEmployeeView,
            ),
          const SizedBox(width: 7),
          const ThemeToggle(),
          const SizedBox(width: 7),
          HaulIconButton(
            icon: Icons.logout_rounded,
            tooltip: 'Sign out and change access level',
            onPressed: state.signOut,
          ),
        ],
      ),
    );
  }
}

/// The promise, stated on screen: dispatch sees you while the app is open, and
/// not after.
class _LocationStrip extends StatelessWidget {
  const _LocationStrip();

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final gps = state.gps;
    final live = gps.state == GpsState.live || gps.state == GpsState.simulated;

    final detail = switch (gps.state) {
      GpsState.live when gps.hasCoords =>
        '${gps.latitude!.toStringAsFixed(4)}, '
            '${gps.longitude!.toStringAsFixed(4)} · updated '
            '${_clock(gps.at)}',
      GpsState.simulated =>
        'Location unavailable here — showing a simulated position',
      GpsState.off => 'Sharing is off',
      _ => 'Getting a fix…',
    };

    return Semantics(
      // Reads out when the fix changes rather than staying a silent icon.
      liveRegion: true,
      label:
          'Sharing location with dispatch. $detail. '
          'Stops when you close the app.',
      excludeSemantics: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        decoration: BoxDecoration(
          color: live ? hc.surface : hc.raised,
          border: Border(bottom: BorderSide(color: hc.line)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // On a phone — or at a large text size — the reminder drops under
            // the status instead of squeezing it into a column of single
            // letters.
            final stacked = constraints.maxWidth < 520;
            final reminder = Pill(label: 'Stops when you close the app');

            final status = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sharing location with dispatch',
                  style: ht.bodyStrong.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 1),
                Text(detail, style: ht.small.copyWith(fontSize: 12)),
                if (stacked) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerLeft, child: reminder),
                ],
              ],
            );

            return Row(
              children: [
                PingDot(live: live, size: 9),
                const SizedBox(width: 6),
                Expanded(child: status),
                if (!stacked) ...[
                  const SizedBox(width: 8),
                  Flexible(child: reminder),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _clock(DateTime? d) {
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

IconData _tabIcon(HaulTab tab) => switch (tab) {
  HaulTab.board => Icons.grid_view_rounded,
  HaulTab.mine => Icons.local_shipping_rounded,
  HaulTab.day => Icons.calendar_today_rounded,
  HaulTab.jobs => Icons.assignment_outlined,
  HaulTab.crew => Icons.people_alt_outlined,
  HaulTab.hours => Icons.schedule_rounded,
  HaulTab.tracking => Icons.navigation_rounded,
  HaulTab.overview => Icons.dashboard_outlined,
};

/// Bottom tabs for handheld layouts.
///
/// Hand-rolled rather than a [NavigationBar] for one reason: Material's
/// destination labels neither shrink nor ellipsize, so four tabs on a 320pt
/// phone at the largest supported text size clip off the right edge. Here each
/// tab is an [Expanded] with a single ellipsised line, so it can't.
class HaulBottomTabs extends StatelessWidget {
  const HaulBottomTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final state = AppScope.of(context);
    final tabs = state.navTabs;
    final current = tabs.indexOf(state.tab).clamp(0, tabs.length - 1);

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(top: BorderSide(color: hc.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          // Not `stretch`: this Row sits in a Column that hands it an
          // unbounded height. Every tab has the same content shape, so they
          // come out the same height anyway.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _Tab(
                  tab: tabs[i],
                  selected: i == current,
                  position: i + 1,
                  total: tabs.length,
                  onTap: () => state.setTab(tabs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.position,
    required this.total,
    required this.onTap,
  });

  final HaulTab tab;
  final bool selected;
  final int position;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final color = selected ? hc.brand : hc.inkSoft;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${tab.label} tab, $position of $total',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            // Selection is carried by the top bar *and* the colour, so it
            // doesn't rest on colour alone.
            border: Border(
              top: BorderSide(
                color: selected ? hc.brand : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_tabIcon(tab), size: 20, color: color),
              const SizedBox(height: 5),
              Text(
                tab.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: ht.eyebrow.copyWith(
                  color: color,
                  letterSpacing: 0.5,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail();

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final tabs = state.navTabs;
    final index = tabs.indexOf(state.tab).clamp(0, tabs.length - 1);

    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: (i) => state.setTab(tabs[i]),
      backgroundColor: hc.surface,
      indicatorColor: hc.brandWash,
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: ht.eyebrow.copyWith(color: hc.ink),
      unselectedLabelTextStyle: ht.eyebrow,
      destinations: [
        for (final t in tabs)
          NavigationRailDestination(
            icon: Icon(_tabIcon(t), color: hc.inkSoft),
            selectedIcon: Icon(_tabIcon(t), color: hc.brand),
            label: Text(t.label),
          ),
      ],
    );
  }
}

/// Transient confirmation. Announced, not just shown.
class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.raised});

  final String message;

  /// Lifted clear of the bottom tab bar on narrow layouts.
  final bool raised;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  /// The message already read out, so a rebuild doesn't repeat it.
  String? _announced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: View.of() looks up an inherited widget, which is only
    // legal from here down.
    _announce();
  }

  @override
  void didUpdateWidget(_Toast old) {
    super.didUpdateWidget(old);
    _announce();
  }

  void _announce() {
    if (_announced == widget.message) return;
    _announced = widget.message;
    // Explicit view rather than the implicit one — the multi-window-safe path.
    SemanticsService.sendAnnouncement(
      View.of(context),
      widget.message,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Positioned(
      left: 14,
      right: 14,
      bottom: widget.raised ? 90 : 20,
      // Transparent to pointers on purpose. A toast floats over the bottom of
      // the screen, which is exactly where the primary action lives — a driver
      // tapping "Close it out" must not have the tap eaten by the confirmation
      // for the photo they just filed. It clears itself instead.
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Material(
            color: hc.raised,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: hc.brand, width: 4)),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Text(widget.message, style: ht.body),
            ),
          ),
        ),
      ),
    );
  }
}

/// The payoff screen after a job closes.
class _ClosedOverlay extends StatelessWidget {
  const _ClosedOverlay({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return Positioned.fill(
      // Nothing behind this matters until it is dismissed.
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: 'Load closed',
        child: ColoredBox(
          // Derived, not hardcoded: this scrim used to be a fixed near-black,
          // which put light-mode ink (which is dark) on a black field.
          color: hc.bg.withValues(alpha: 0.94),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: hc.go,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 46,
                        color: hc.onBrand,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      child: Text(
                        'LOAD CLOSED',
                        style: ht.display.copyWith(fontSize: 26),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${job.type} for ${job.customer} — photos filed, '
                      'movement log sent to dispatch, ticket to billing.',
                      textAlign: TextAlign.center,
                      style: ht.secondary,
                    ),
                    const SizedBox(height: 20),
                    // The hours, not a figure. A driver is paid for their time,
                    // and what that time is worth is between them and payroll —
                    // not something the app announces at the end of every job.
                    Semantics(
                      label:
                          'Time on this job, '
                          '\${describeWorked(job.workedBy(DateTime.now()))}',
                      excludeSemantics: true,
                      child: Text(
                        formatWorked(job.workedBy(DateTime.now())),
                        style: ht.money.copyWith(fontSize: 32),
                      ),
                    ),
                    Text('on the clock', style: ht.small),
                    const SizedBox(height: 24),
                    FilledButton(
                      autofocus: true,
                      onPressed: state.dismissClosedJob,
                      style: FilledButton.styleFrom(
                        backgroundColor: hc.brand,
                        foregroundColor: hc.onBrand,
                        minimumSize: const Size(240, HaulSpace.tap),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'BACK TO THE BOARD',
                        style: ht.action.copyWith(color: hc.onBrand),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
