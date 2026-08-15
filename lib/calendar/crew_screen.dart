import 'package:flutter/material.dart';

import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/role.dart';
import '../models/time_entry.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'form_bits.dart';

/// Where everybody is, and what they have put in.
///
/// An owner's screen, and the answer to the standing question in a yard this
/// size: who is out, on what, and since when. Everything on it is derived —
/// the jobs are the record and the hours are the jobs' own stamps — so there
/// is nothing here anybody has to remember to update.
Future<void> showCrew(BuildContext context) {
  final cal = CalendarScope.read(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CalendarScope(state: cal, child: const CrewScreen()),
    ),
  );
}

/// The roster in the order somebody scanning it wants to read it.
///
/// Whoever is out comes first, then whoever is on shift, then the rest, and
/// names inside each band. Alphabetical alone buries the one person you opened
/// this screen to find under three who are sat at home.
List<CrewMember> crewInOrder(AppState app) {
  int rank(CrewMember m) {
    if (app.jobInHand(m) != null) return 0;
    if (m.onShift) return 1;
    return 2;
  }

  return [...app.crew]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.name.compareTo(b.name);
  });
}

class CrewScreen extends StatelessWidget {
  const CrewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    final crew = crewInOrder(app);

    return Scaffold(
      backgroundColor: p.groupedBg,
      appBar: AppBar(
        backgroundColor: p.groupedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Crew', style: t.navTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done', style: t.body.copyWith(color: p.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Standing(),
          if (crew.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Nobody is on the books yet.',
                textAlign: TextAlign.center,
                style: t.secondary,
              ),
            ),
          for (final member in crew) _Person(member: member),
          if (app.canHire) const _Hire(),
        ],
      ),
    );
  }
}

/// Putting somebody on the books.
///
/// What it offers comes from [AppState.hirableRoles], and the state refuses
/// anything outside it anyway — a form is where you offer the right choices,
/// not where you enforce them.
class _Hire extends StatefulWidget {
  const _Hire();

  @override
  State<_Hire> createState() => _HireState();
}

class _HireState extends State<_Hire> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  Role? _level;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final app = AppScope.read(context);
    final level = _level ?? app.hirableRoles.first;
    if (_name.text.trim().isEmpty) {
      app.showToast('Say who you are taking on.');
      return;
    }

    setState(() => _busy = true);
    final ok = await app.hire(name: _name.text, role: level, unit: _unit.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _name.clear();
        _unit.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final offered = app.hirableRoles;
    final level = _level ?? offered.first;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Take somebody on', style: t.bodyStrong),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                FormRow(
                  label: 'Name',
                  controller: _name,
                  hint: 'Who is joining',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
                FormRow(
                  label: 'Unit',
                  controller: _unit,
                  hint: 'The truck they run, if any',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
                ChoiceRow<Role>(
                  label: 'Level',
                  shown: level.label,
                  ticked: (role) => role == level,
                  choices: [for (final role in offered) (role, role.label)],
                  onChanged: (role) => setState(() => _level = role),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              // Said plainly, because a name on the roster that cannot sign in
              // looks like a broken app rather than a job half done.
              'They go on the roster off shift, with no way in until you give '
              'them a login.',
              style: t.secondary.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: 'Add to the crew',
            onTap: _busy ? null : _go,
            excludeSemantics: true,
            child: FilledButton(
              onPressed: _busy ? null : _go,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                'Add to the crew',
                style: t.bodyStrong.copyWith(fontSize: 16, color: p.onAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line answer, before anybody reads a row.
class _Standing extends StatelessWidget {
  const _Standing();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    final out = app.working.length;
    final driving = app.moving.length;
    final reporting = app.crew.where((c) => c.appOpen).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          out == 0
              ? 'Nobody has a job in hand. '
                    '$reporting of ${app.crew.length} have the app open.'
              : '$out of ${app.crew.length} out on a job'
                    '${driving == 0 ? '' : ', $driving between stops'}. '
                    '$reporting reporting.',
          style: t.body.copyWith(fontSize: 15),
        ),
      ),
    );
  }
}

/// One person: who they are, what they have, where they were, what they put in.
class _Person extends StatelessWidget {
  const _Person({required this.member});

  final CrewMember member;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    final job = app.jobInHand(member);
    final sheet = app.timesheetFor(member);
    final today = app.hoursToday(member);
    final running = sheet.onTheClock;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Semantics(
        label: _spoken(app, member, job, sheet, today),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(member: member, running: running),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: t.bodyStrong.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        member.unit.isEmpty
                            ? member.role.label
                            : '${member.role.label} · ${member.unit}',
                        style: t.secondary.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // The figure somebody actually came for, kept out on the
                // right where the eye can run down a column of them.
                Text(
                  today == Duration.zero ? '—' : formatWorked(today),
                  style: t.bodyStrong.copyWith(
                    fontSize: 16,
                    color: running ? p.accent : p.label,
                  ),
                ),
              ],
            ),
            // Moving somebody between levels is an owner's, and never their
            // own — the state refuses that, and offering it here would be a
            // button whose only outcome is a refusal.
            if (app.canSetRoles && member.id != app.meId)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ChoiceRow<Role>(
                  label: 'Level',
                  spokenLabel: 'Level for ${member.name}',
                  shown: member.role.label,
                  ticked: (role) => role == member.role,
                  choices: [for (final role in Role.values) (role, role.label)],
                  onChanged: (role) => app.setCrewRole(member, role),
                ),
              ),
            const SizedBox(height: 10),
            _Line(icon: Icons.local_shipping_rounded, text: _doing(job)),
            const SizedBox(height: 4),
            _Line(icon: Icons.place_rounded, text: _whereabouts(member)),
            const SizedBox(height: 4),
            _Line(
              icon: Icons.schedule_rounded,
              text: _hours(app, sheet, today),
            ),
          ],
        ),
      ),
    );
  }

  /// What they have in hand, in the words dispatch would use.
  String _doing(Job? job) {
    if (job == null) return 'Nothing in hand';
    return '${job.id} · ${job.phase.label} · ${job.customer}';
  }

  /// Where they were last, and how much that is worth knowing.
  ///
  /// The app only reports position while somebody has it open — that is the
  /// promise made to drivers — so a closed app is said plainly rather than
  /// dressed up as a stale fix.
  String _whereabouts(CrewMember member) {
    if (member.appOpen) {
      final place = member.lastPlace;
      return place == null || place.isEmpty
          ? 'Reporting now'
          : 'Reporting now · $place';
    }
    final seen = member.lastSeen;
    final place = member.lastPlace;
    if (seen == null && place == null) {
      return 'Not reporting — the app is closed';
    }
    return 'App closed. Last seen '
        '${[?place, ?seen].join(', ')}';
  }

  String _hours(AppState app, Timesheet sheet, Duration today) {
    final all = formatWorked(sheet.worked);
    final pay = sheet.pay;
    final base =
        '${today == Duration.zero ? 'Nothing today' : '${formatWorked(today)} today'} · $all all told';
    if (!app.canSeeHoursAndPay) return base;
    return pay == null ? '$base · no rate set' : '$base · \$$pay';
  }

  String _spoken(
    AppState app,
    CrewMember member,
    Job? job,
    Timesheet sheet,
    Duration today,
  ) {
    final level = member.role.label.toLowerCase();
    return '${member.name}, $level. ${_doing(job)}. '
        '${_whereabouts(member)}. ${_hours(app, sheet, today)}.';
  }
}

/// Initials in a circle, ringed while the clock is running.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.member, required this.running});

  final CrewMember member;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: running ? p.accent : p.fill,
        shape: BoxShape.circle,
        border: member.appOpen
            ? Border.all(color: p.accent, width: 2)
            : Border.all(color: p.hairline, width: 1),
      ),
      child: Text(
        member.initials.isEmpty ? initialsFor(member.name) : member.initials,
        style: t.bodyStrong.copyWith(
          fontSize: 14,
          color: running ? p.onAccent : p.secondaryLabel,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: p.tertiaryLabel),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: t.secondary.copyWith(fontSize: 13))),
      ],
    );
  }
}
