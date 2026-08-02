import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

/// The device sizes this app is expected to survive, smallest first.
///
/// The 320-wide entry is a small phone in portrait; 1440 is a maximised desktop
/// window. Everything in between is an iPad, a split-screen tablet, or a
/// resized desktop window.
const sizes = <String, Size>{
  'small phone': Size(320, 640),
  'phone': Size(420, 900),
  'tablet portrait': Size(834, 1112),
  'tablet landscape': Size(1194, 834),
  'desktop': Size(1440, 900),
  'narrow desktop window': Size(700, 620),
};

/// Every tab, by the role that can reach it.
const tabsByRole = <Role, List<HaulTab>>{
  Role.employee: [HaulTab.board, HaulTab.mine],
  Role.manager: [HaulTab.jobs, HaulTab.crew, HaulTab.board],
  Role.admin: [HaulTab.overview, HaulTab.tracking, HaulTab.jobs, HaulTab.crew],
};

void main() {
  // A layout that overflows is content the driver cannot see. Sweeping every
  // tab across every size at both normal and enlarged text is the cheapest way
  // to keep six platforms honest.
  group('no tab overflows at any supported size', () {
    for (final entry in sizes.entries) {
      for (final roleEntry in tabsByRole.entries) {
        for (final tab in roleEntry.value) {
          for (final scale in [1.0, 1.6]) {
            testWidgets(
              '${entry.key} · ${roleEntry.key.label} · ${tab.label} · '
              'text ${scale}x',
              (tester) async {
                final harness = await pumpApp(
                  tester,
                  role: roleEntry.key,
                  size: entry.value,
                  textScale: scale,
                );
                harness.state.setTab(tab);
                await settle(tester);

                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });

  group('no job card overflows at any supported size', () {
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('${entry.key} · text ${scale}x', (tester) async {
          final harness = await pumpApp(
            tester,
            role: Role.manager,
            size: entry.value,
            textScale: scale,
          );

          // Open every job in turn — they differ in hazard count, disposal
          // stop, and whether a driver is on them.
          for (final job in harness.state.jobs) {
            harness.state.openJobCard(job);
            await settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '${job.id} at ${entry.key}',
            );
          }
        });
      }
    }
  });

  testWidgets('the closed-job overlay fits the smallest screen', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      role: Role.employee,
      size: const Size(320, 640),
      textScale: 1.6,
    );

    harness.state.claim(jobIn(harness.state, 'HL-4471'));
    for (var i = 0; i < 4; i++) {
      harness.state.advance(jobIn(harness.state, 'HL-4471'));
    }
    await harness.state.addPhoto(jobIn(harness.state, 'HL-4471'), before: true);
    await harness.state.addPhoto(
      jobIn(harness.state, 'HL-4471'),
      before: false,
    );
    harness.state.advance(jobIn(harness.state, 'HL-4471'));
    await settle(tester);

    expect(find.text('LOAD CLOSED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the role gate fits the smallest screen at large text', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(320, 640), textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(find.text('EMPLOYEE'), findsOneWidget);
  });
}
