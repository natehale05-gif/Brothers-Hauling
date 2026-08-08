import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/price_sheet.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// A job on the pinned day, at nine, priced or not as the caller likes.
Job priced(String id, {int billed = 0, int dumpFee = 0, JobStatus? status}) {
  // Money is not in copyWith — dispatch corrects a price through EditJob, not
  // by rebuilding the record — so the fixture goes through the wire format.
  final base = job(id, at: DateTime(2026, 8, 6, 9)).copyWith(
    status: status ?? (billed > 0 ? JobStatus.open : JobStatus.requested),
  );
  return Job.fromJson({...base.toJson(), 'billed': billed, 'dumpFee': dumpFee});
}

/// Opens the job, then its price sheet.
Future<void> openPricer(WidgetTester tester) async {
  await tester.tap(find.text('Debris haul').first);
  await settle(tester);
  await tester.tap(find.bySemanticsLabel('Price job'));
  await settle(tester);
}

void main() {
  group('who may price', () {
    testWidgets('an owner is offered it', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      expect(app.state.canPriceJobs, isTrue);
      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.bySemanticsLabel('Price job'), findsOneWidget);
    });

    testWidgets('so is a manager', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      expect(app.state.canPriceJobs, isTrue);
      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.bySemanticsLabel('Price job'), findsOneWidget);
      // Pricing is not editing. The rest of the job stays the owner's.
      expect(app.state.canEditJobs, isFalse);
      expect(find.bySemanticsLabel('Edit job'), findsNothing);
    });

    testWidgets('a driver is not', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      expect(app.state.canPriceJobs, isFalse);
      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.bySemanticsLabel('Price job'), findsNothing);
      // Nor the figure itself.
      expect(find.text('\$300'), findsNothing);
    });
  });

  group('putting a number on a job', () {
    testWidgets('a manager types one and it lands on the board', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300, dumpFee: 40)],
      );

      await openPricer(tester);
      expect(find.byType(PriceSheet), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '525');
      await tester.enterText(find.byType(TextField).last, '75');
      await settle(tester);

      // The arithmetic is shown while it is being typed, not after saving.
      expect(find.textContaining('\$450 after the tip'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await settle(tester);

      final after = jobIn(app.state, 'HL-1');
      expect(after.billed, 525);
      expect(after.dumpFee, 75);
    });

    testWidgets('a typed dollar sign and commas are still a number', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      await openPricer(tester);
      await tester.enterText(find.byType(TextField).first, '\$1,250.00');
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').billed, 1250);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      await openPricer(tester);
      await tester.enterText(find.byType(TextField).first, '999');
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').billed, 300);
    });

    testWidgets('a tip that costs more than the job says so', (tester) async {
      await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1', billed: 300)],
      );

      await openPricer(tester);
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.enterText(find.byType(TextField).last, '160');
      await settle(tester);

      expect(find.textContaining('costs more than the job bills'), findsOne);
    });
  });

  group('a booking off the website', () {
    testWidgets('offers the way to price it, not just the news', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1')],
      );

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.text('Put a price on it'), findsOneWidget);
    });

    testWidgets('a driver only gets told why they cannot take it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [priced('HL-1')],
      );

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.text('Put a price on it'), findsNothing);
      expect(find.textContaining('until it has a price'), findsOneWidget);
    });

    testWidgets('pricing and publishing happen in one press', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1')],
      );

      expect(jobIn(app.state, 'HL-1').status, JobStatus.requested);

      await openPricer(tester);
      await tester.enterText(find.byType(TextField).first, '480');
      await settle(tester);
      await tester.tap(find.text('Put it on the board'));
      await settle(tester);

      final after = jobIn(app.state, 'HL-1');
      expect(after.billed, 480);
      expect(after.status, JobStatus.open, reason: 'the crew can see it now');
    });

    testWidgets('and it cannot go up at no price at all', (tester) async {
      await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [priced('HL-1')],
      );

      await openPricer(tester);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Put it on the board'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
