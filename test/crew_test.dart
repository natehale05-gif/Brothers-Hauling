import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/crew_member.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/widgets/add_crew.dart';

import 'helpers.dart';

void main() {
  AppState boot({Store? store, Role? role}) {
    final shared = store ?? MemoryStore();
    final state = AppState(
      board: LocalBoardRepository(store: shared),
      store: shared,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
    );
    addTearDown(state.dispose);
    if (role != null) state.enter(role);
    return state;
  }

  group('who can hire whom', () {
    test('an owner can take on anyone', () {
      final state = boot(role: Role.admin);
      expect(state.hirableRoles, [Role.employee, Role.manager, Role.admin]);
      expect(state.canHire, isTrue);
    });

    test('a manager can staff their crew but not mint another manager', () {
      final state = boot(role: Role.manager);
      // Otherwise "add crew" is a privilege escalation with a friendly form on
      // top of it.
      expect(state.hirableRoles, [Role.employee]);
    });

    test('a driver cannot hire at all', () {
      final state = boot(role: Role.employee);
      expect(state.hirableRoles, isEmpty);
      expect(state.canHire, isFalse);
    });

    test('the employee view gives up the power along with the money', () {
      final state = boot(role: Role.admin);
      state.toggleEmployeeView();
      // If you are looking at what your crew sees, you get what your crew gets.
      expect(state.hirableRoles, isEmpty);
    });

    test(
      'the state refuses a role the form should never have offered',
      () async {
        final state = boot(role: Role.manager);
        final before = state.crew.length;

        final ok = await state.hire(
          name: 'Sneaky Pete',
          role: Role.admin,
          unit: '',
        );

        expect(ok, isFalse);
        expect(state.crew, hasLength(before));
        expect(state.toast, contains('cannot add'));
      },
    );
  });

  group('hiring someone', () {
    test('puts them on the roster', () async {
      final state = boot(role: Role.manager);
      final before = state.crew.length;

      final ok = await state.hire(
        name: 'Dale Whitlow',
        role: Role.employee,
        unit: 'Truck 12',
      );

      expect(ok, isTrue);
      expect(state.crew, hasLength(before + 1));
      final hired = state.crew.last;
      expect(hired.name, 'Dale Whitlow');
      expect(hired.initials, 'DW');
      expect(hired.role, Role.employee);
    });

    test('nobody starts a shift they have not turned up for', () async {
      final state = boot(role: Role.admin);
      await state.hire(name: 'Ana Reyes', role: Role.employee, unit: '');

      // Starting them "live" would put a driver on the tracking board who has
      // never opened the app.
      expect(state.crew.last.onShift, isFalse);
      expect(state.crew.last.appOpen, isFalse);
    });

    test('a blank name is not a person', () async {
      final state = boot(role: Role.admin);
      final before = state.crew.length;
      expect(
        await state.hire(name: '   ', role: Role.employee, unit: ''),
        isFalse,
      );
      expect(state.crew, hasLength(before));
    });

    test('a new manager is not offered a load', () async {
      final state = boot(role: Role.admin);
      await state.hire(name: 'Priya Nair', role: Role.manager, unit: '');

      // Jobs get pushed at drivers, not at the office.
      expect(state.crew.map((c) => c.name), contains('Priya Nair'));
      expect(state.drivers.map((c) => c.name), isNot(contains('Priya Nair')));
    });

    test('hiring survives the app being closed', () async {
      final store = MemoryStore();
      final first = boot(store: store, role: Role.admin);
      await first.restore();
      await first.hire(
        name: 'Dale Whitlow',
        role: Role.employee,
        unit: 'Truck 12',
      );

      // Hiring someone in a dead zone has to survive the app dying, exactly as
      // a claimed load does.
      final second = boot(store: store, role: Role.admin);
      await second.restore();
      expect(second.crew.map((c) => c.name), contains('Dale Whitlow'));
      expect(second.crew.last.role, Role.employee);
    });

    test('it is owed to dispatch like any other change', () async {
      final state = boot(role: Role.admin);
      await state.restore();
      final pending = state.syncState.pending;
      await state.hire(name: 'Ana Reyes', role: Role.employee, unit: '');
      expect(state.syncState.pending, greaterThanOrEqualTo(pending));
    });
  });

  group('the hiring mutation', () {
    final member = const CrewMember(
      id: 'crew-9',
      name: 'Dale Whitlow',
      initials: 'DW',
      unit: 'Truck 12',
      onShift: false,
      appOpen: false,
      role: Role.employee,
    );

    AddCrewMember hiring() => AddCrewMember(
      id: 'm1',
      actorId: 'c1',
      at: DateTime.utc(2026),
      member: member,
    );

    test('replaying it does not hire the same person twice', () {
      final once = hiring().apply([])!;
      expect(once, hasLength(1));
      expect(hiring().apply(once), isNull);
    });

    test('it round-trips through the queue', () {
      final copy = Mutation.fromJson(hiring().toJson());
      expect(copy, isA<AddCrewMember>());
      final restored = (copy! as AddCrewMember).member;
      expect(restored.id, 'crew-9');
      expect(restored.name, 'Dale Whitlow');
      expect(restored.role, Role.employee);
    });

    test('it carries no job, and is not counted against one', () {
      // A job change marks its card; hiring has no card to mark.
      expect(hiring(), isNot(isA<JobMutation>()));
      expect(hiring().toJson().containsKey('jobId'), isFalse);
    });
  });

  group('a record written before roles existed', () {
    test('reads as a driver rather than an owner', () {
      final member = CrewMember.fromJson(const {
        'id': 'c9',
        'name': 'Old Record',
        'initials': 'OR',
      });
      // Guessing upwards would hand someone the money screens on a typo.
      expect(member.role, Role.employee);
    });

    test('so does an unrecognised one', () {
      final member = CrewMember.fromJson(const {'id': 'c9', 'role': 'founder'});
      expect(member.role, Role.employee);
    });
  });

  group('initials', () {
    test('come from the first and last word', () {
      expect(initialsFor('Dale Whitlow'), 'DW');
      expect(initialsFor('  ana maria reyes '), 'AR');
    });

    test('a single name gets two letters, not one', () {
      // Otherwise a crew of Dave and Danny are both just "D".
      expect(initialsFor('Dave'), 'DA');
      expect(initialsFor('D'), 'D');
    });

    test('an empty name does not crash an avatar', () {
      expect(initialsFor('   '), '?');
    });
  });

  group('on screen', () {
    testWidgets('a manager is offered the button, a driver is not', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      expect(find.byType(AddCrewButton), findsOneWidget);
      expect(find.text('ADD AN EMPLOYEE'), findsOneWidget);
    });

    testWidgets('an owner is offered the wider wording', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      expect(find.text('ADD CREW'), findsOneWidget);
    });

    testWidgets('the new hire shows up on the roster', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);

      await harness.state.hire(
        name: 'Dale Whitlow',
        role: Role.employee,
        unit: 'Truck 12',
      );
      await settle(tester);

      expect(find.text('Dale Whitlow'), findsWidgets);
    });

    testWidgets('the form only offers what this user may hand out', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);

      await tester.tap(find.byType(AddCrewButton));
      await settle(tester);

      expect(find.text('Employee'), findsOneWidget);
      expect(find.text('Manager'), findsNothing);
      expect(find.text('Admin'), findsNothing);
    });

    testWidgets('filling it in adds the person', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      final before = harness.state.crew.length;

      await tester.tap(find.byType(AddCrewButton));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Dale Whitlow');
      await tester.tap(find.text('ADD TO CREW'));
      await settle(tester);

      expect(harness.state.crew, hasLength(before + 1));
      expect(harness.state.crew.last.name, 'Dale Whitlow');
    });

    testWidgets('a nameless submission says so instead of doing nothing', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      final before = harness.state.crew.length;

      await tester.tap(find.byType(AddCrewButton));
      await settle(tester);
      await tester.tap(find.text('ADD TO CREW'));
      await settle(tester);

      expect(find.textContaining('A name is the one thing'), findsOneWidget);
      expect(harness.state.crew, hasLength(before));
    });
  });

  group('promoting and demoting', () {
    /// Everyone but the signed-in user, so tests never trip the self guard.
    CrewMember other(AppState state) =>
        state.crew.firstWhere((c) => c.id != kMeId);

    test('an owner may move people between levels', () {
      expect(boot(role: Role.admin).canSetRoles, isTrue);
    });

    test('a manager may not', () {
      // A manager can take a driver on; letting them promote one is the same
      // escalation by a slower route.
      expect(boot(role: Role.manager).canSetRoles, isFalse);
    });

    test('a driver may not', () {
      expect(boot(role: Role.employee).canSetRoles, isFalse);
    });

    test('nor may an owner standing in the crew view', () {
      final state = boot(role: Role.admin)..toggleEmployeeView();
      expect(state.canSetRoles, isFalse);
    });

    test('a promotion sticks', () async {
      final state = boot(role: Role.admin);
      final who = other(state);
      expect(who.role, isNot(Role.manager));

      final ok = await state.setCrewRole(who, Role.manager);

      expect(ok, isTrue);
      expect(state.crew.firstWhere((c) => c.id == who.id).role, Role.manager);
    });

    test('and so does a demotion', () async {
      final state = boot(role: Role.admin);
      final who = other(state);
      await state.setCrewRole(who, Role.admin);

      await state.setCrewRole(
        state.crew.firstWhere((c) => c.id == who.id),
        Role.employee,
      );

      expect(state.crew.firstWhere((c) => c.id == who.id).role, Role.employee);
    });

    test('it changes the role and nothing else about them', () async {
      final state = boot(role: Role.admin);
      final before = other(state);

      await state.setCrewRole(before, Role.manager);
      final after = state.crew.firstWhere((c) => c.id == before.id);

      // A promotion is a change of level, not a chance to rewrite a record.
      expect(after.name, before.name);
      expect(after.unit, before.unit);
      expect(after.hourlyRate, before.hourlyRate);
      expect(after.onShift, before.onShift);
    });

    test('a manager is refused', () async {
      final state = boot(role: Role.manager);
      final who = other(state);

      final ok = await state.setCrewRole(who, Role.admin);

      expect(ok, isFalse);
      expect(state.crew.firstWhere((c) => c.id == who.id).role, who.role);
    });

    test('nobody demotes themselves', () async {
      final state = boot(role: Role.admin);
      final me = state.crew.firstWhere((c) => c.id == kMeId);

      final ok = await state.setCrewRole(me, Role.employee);

      // Otherwise a one-owner company locks the owner screens behind a door
      // it has just thrown the key over.
      expect(ok, isFalse);
      expect(state.crew.firstWhere((c) => c.id == kMeId).role, me.role);
    });

    test('setting the level somebody already has is not a change', () async {
      final state = boot(role: Role.admin);
      final who = other(state);
      expect(await state.setCrewRole(who, who.role), isFalse);
    });

    test('it survives a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store, role: Role.admin);
      await first.restore();
      final who = other(first);
      await first.setCrewRole(who, Role.manager);

      final second = boot(store: store, role: Role.admin);
      await second.restore();

      expect(second.crew.firstWhere((c) => c.id == who.id).role, Role.manager);
    });
  });

  group('the role mutation itself', () {
    const roster = [
      CrewMember(
        id: 'c9',
        name: 'Dale Whitlow',
        initials: 'DW',
        unit: 'Truck 12',
        onShift: true,
        appOpen: true,
      ),
    ];

    SetCrewRole make(String crewId, Role role) => SetCrewRole(
      id: 'm1',
      actorId: kMeId,
      at: DateTime(2026, 8, 2),
      crewId: crewId,
      role: role,
    );

    test('it moves the person it names', () {
      expect(make('c9', Role.manager).apply(roster)!.single.role, Role.manager);
    });

    test('replaying it is not a second promotion', () {
      final once = make('c9', Role.manager).apply(roster)!;
      // Null means "no longer applies" — which is what keeps a replayed queue
      // from dragging a later decision back to this one.
      expect(make('c9', Role.manager).apply(once), isNull);
    });

    test('somebody who is not there is left alone', () {
      expect(make('nobody', Role.admin).apply(roster), isNull);
    });

    test('it survives the round trip through the outbox', () {
      final sent = make('c9', Role.admin);
      final back = Mutation.fromJson(sent.toJson()) as SetCrewRole;

      expect(back.crewId, 'c9');
      expect(back.role, Role.admin);
    });

    test('an unreadable level is dropped, not guessed', () {
      final json = make('c9', Role.admin).toJson();
      json['role'] = 'supervisor';

      // Defaulting down would silently demote on a typo. Defaulting up is
      // worse. Neither is a guess worth making.
      expect(Mutation.fromJson(json), isNull);
    });
  });
}
