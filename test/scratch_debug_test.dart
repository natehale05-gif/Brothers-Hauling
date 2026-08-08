import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';

import 'calendar_view_test.dart' show bookedJobs;
import 'helpers.dart';

void main() {
  testWidgets('dump day semantics', (tester) async {
    await pumpApp(tester, view: CalView.day, jobs: bookedJobs());
    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .where((l) => l != null && l.isNotEmpty)
        .toList();
    debugPrint('DAY LABELS: $labels');
  });

  testWidgets('tap a row in month', (tester) async {
    final app = await pumpApp(tester, jobs: bookedJobs());
    debugPrint(
      'MONTH TEXTS: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
    );
    await tester.tap(find.text('Junk removal').last);
    await settle(tester);
    debugPrint('OPEN: ${app.calendar.openEventId}');
  });
}
