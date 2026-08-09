import 'package:flutter/material.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'date_math.dart';
import 'event.dart';

/// Does [job] answer to [query]?
///
/// Every word has to appear somewhere, in any field and in any order — "junk
/// corvallis" finds the Corvallis junk job whichever way round it is typed,
/// which is how anybody actually searches a calendar.
bool jobMatches(Job job, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return false;

  final haystack = [
    job.id,
    job.type,
    job.customer,
    job.address,
    job.city,
    job.contact,
    job.phone,
    job.material,
    job.equipmentLabel,
    job.access,
    job.disposal,
  ].join(' ').toLowerCase();

  return words.every(haystack.contains);
}

/// Every job answering to [query], soonest first.
///
/// Undated work comes last rather than being dropped: a booking nobody has
/// scheduled is exactly the kind of thing somebody searches for.
List<Job> searchJobs(Iterable<Job> jobs, String query) {
  final hits = [
    for (final job in jobs)
      if (jobMatches(job, query)) job,
  ];
  hits.sort((a, b) {
    final left = a.scheduledFor;
    final right = b.scheduledFor;
    if (left == null && right == null) return a.id.compareTo(b.id);
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });
  return hits;
}

/// Apple's search: a field at the top, results underneath, and picking one
/// takes you to the day it is on.
Future<void> showCalendarSearch(BuildContext context) {
  final cal = CalendarScope.read(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CalendarScope(state: cal, child: const CalendarSearch()),
    ),
  );
}

class CalendarSearch extends StatefulWidget {
  const CalendarSearch({super.key});

  @override
  State<CalendarSearch> createState() => _CalendarSearchState();
}

class _CalendarSearchState extends State<CalendarSearch> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(Job job) {
    final cal = CalendarScope.read(context);
    final at = job.scheduledFor;
    if (at != null) {
      cal.focus(at);
      cal.setView(CalView.day);
    }
    cal.openEvent(job.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final query = _query.text.trim();
    final hits = query.isEmpty ? const <Job>[] : searchJobs(app.jobs, query);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 12,
        // Done dismisses this; a second X beside it is one exit too many and
        // takes the room the field wants.
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          style: t.body.copyWith(fontSize: 16),
          decoration: InputDecoration(
            filled: true,
            fillColor: p.fill,
            isDense: true,
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: p.secondaryLabel,
            ),
            hintText: 'Search jobs',
            hintStyle: t.body.copyWith(fontSize: 16, color: p.tertiaryLabel),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done', style: t.body.copyWith(color: p.accent)),
          ),
        ],
      ),
      body: query.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Search by customer, town, kind of work, what it needs, or '
                  'the job number.',
                  textAlign: TextAlign.center,
                  style: t.secondary,
                ),
              ),
            )
          : hits.isEmpty
          ? Center(
              child: Semantics(
                liveRegion: true,
                child: Text('Nothing matches "$query".', style: t.secondary),
              ),
            )
          : Semantics(
              liveRegion: true,
              label:
                  '${hits.length} '
                  '${hits.length == 1 ? 'job' : 'jobs'} found',
              child: ListView.separated(
                itemCount: hits.length,
                separatorBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
                itemBuilder: (context, i) =>
                    _Hit(job: hits[i], onTap: () => _open(hits[i])),
              ),
            ),
    );
  }
}

class _Hit extends StatelessWidget {
  const _Hit({required this.job, required this.onTap});

  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final calendar = WorkCalendar.of(job);
    final at = job.scheduledFor;
    final when = at == null
        ? 'Not scheduled'
        : (at.hour == 0 && at.minute == 0
              ? '${shortDate(at)} · all-day'
              : '${shortDate(at)} · ${clockLabel(at)}');
    final where = [job.customer, if (job.city.isNotEmpty) job.city].join(' · ');

    return Semantics(
      button: true,
      label: '${job.type} for $where. $when.',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: calendar.colour,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      job.type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                    Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.secondary,
                    ),
                    Text(
                      when,
                      maxLines: 1,
                      style: t.secondary.copyWith(
                        fontSize: 13,
                        color: at == null ? p.accent : p.tertiaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple's "go to date" — somewhere far off, without paging there.
Future<void> showGoToDate(BuildContext context) async {
  final cal = CalendarScope.read(context);
  final picked = await showDatePicker(
    context: context,
    initialDate: cal.focused,
    firstDate: DateTime(cal.today.year - 4),
    lastDate: DateTime(cal.today.year + 4),
    helpText: 'Go to date',
  );
  if (picked != null) cal.focus(picked);
}
