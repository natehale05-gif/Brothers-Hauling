import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/intake.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

/// A website that can be switched off, the way a website can be.
class _Website implements IntakeSource {
  List<BookingRequest> bookings = [];
  bool broken = false;
  int fetches = 0;

  @override
  Future<List<BookingRequest>> fetch() async {
    fetches++;
    if (broken) throw StateError('the website is down');
    return bookings;
  }
}

BookingRequest booking(
  String id, {
  String customer = 'Sunset Ridge Builders',
  DateTime? at,
}) => BookingRequest(
  id: id,
  requestedAt: at ?? DateTime.utc(2026, 8, 4, 9),
  customer: customer,
  contact: 'Marla',
  phone: '555-0142',
  address: '1180 Decker Rd',
  city: 'Philomath',
  type: 'Debris haul',
  details: 'Two pallets of broken drywall behind the garage.',
  window: 'Weekday mornings',
);

void main() {
  late _Website website;

  setUp(() => website = _Website());

  AppState boot({Store? store, Role? role, IntakeSource? intake}) {
    final shared = store ?? MemoryStore();
    final state = AppState(
      board: LocalBoardRepository(store: shared),
      store: shared,
      intake: intake ?? website,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
    );
    addTearDown(state.dispose);
    if (role != null) state.enter(role);
    return state;
  }

  group('a booking becomes a job', () {
    test('it lands on the board', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];

      expect(await state.checkForBookings(), 1);

      final job = state.requestedJobs.single;
      expect(job.customer, 'Sunset Ridge Builders');
      expect(job.address, '1180 Decker Rd');
      expect(job.city, 'Philomath');
      expect(job.contact, 'Marla');
      expect(job.phone, '555-0142');
      expect(job.bookingId, 'bk-1');
      expect(job.fromWebsite, isTrue);
    });

    test('what the customer typed reaches the driver', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];
      await state.checkForBookings();

      // The details box is the one place a customer says anything useful; it
      // goes into the access notes rather than being thrown away.
      expect(state.requestedJobs.single.access, contains('broken drywall'));
    });

    test('nothing the customer cannot know is invented', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];
      await state.checkForBookings();

      // A made-up mileage looks exactly like a real one on the board, which is
      // worse than an obviously empty field.
      final job = state.requestedJobs.single;
      expect(job.miles, 0);
      expect(job.payout, 0);
      expect(job.billed, 0);
      expect(job.equipment, isEmpty);
      expect(job.needsPricing, isTrue);
    });

    test('it is kept off the driver board until it is priced', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];
      await state.checkForBookings();

      // An unpriced job on the board is a job somebody can volunteer for at
      // nothing a load.
      expect(state.openBoard.map((j) => j.bookingId), isNot(contains('bk-1')));
      expect(state.requestedJobs, hasLength(1));
    });

    test('it gets a job number that reads out loud', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];
      await state.checkForBookings();

      // "HL-4492" is what gets said down a phone; an opaque device id is not.
      expect(state.requestedJobs.single.id, matches(RegExp(r'^HL-\d+$')));
    });

    test('bookings arrive oldest first', () async {
      final state = boot(role: Role.admin);
      website.bookings = [
        booking('bk-late', at: DateTime.utc(2026, 8, 4, 17)),
        booking('bk-early', at: DateTime.utc(2026, 8, 4, 6)),
      ];
      await state.checkForBookings();

      final ids = state.requestedJobs.map((j) => j.bookingId).toList();
      expect(ids.last, 'bk-early', reason: 'newest first on the board');
    });
  });

  group('the same booking never lands twice', () {
    test('polling again changes nothing', () async {
      final state = boot(role: Role.admin);
      website.bookings = [booking('bk-1')];

      expect(await state.checkForBookings(), 1);
      expect(await state.checkForBookings(), 0);
      expect(await state.checkForBookings(), 0);
      expect(state.requestedJobs, hasLength(1));
    });

    test('nor does a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store, role: Role.admin);
      await first.restore();
      expect(first.requestedJobs, isEmpty);

      website.bookings = [booking('bk-1')];
      await first.checkForBookings();

      final second = boot(store: store, role: Role.admin);
      await second.restore();

      // restore() polls again, and the website still has the booking.
      expect(second.requestedJobs, hasLength(1));
    });

    test('the mutation refuses a duplicate even if the caller does not', () {
      final job = booking('bk-1').toJob('HL-9001');
      final create = CreateJob(
        id: 'm1',
        actorId: 'c1',
        at: DateTime.utc(2026),
        job: job,
      );
      final again = CreateJob(
        id: 'm2',
        actorId: 'c1',
        at: DateTime.utc(2026),
        // A fresh job id, the same booking behind it.
        job: booking('bk-1').toJob('HL-9002'),
      );

      final board = create.apply([])!;
      expect(board, hasLength(1));
      expect(again.apply(board), isNull);
    });
  });

  group('a website that is down', () {
    test('does not take the board with it', () async {
      final state = boot(role: Role.admin);
      website.broken = true;

      expect(await state.checkForBookings(), 0);
      expect(state.jobs, isNotEmpty, reason: 'the board is still there');
    });

    test('nor does a launch while it is down', () async {
      final state = boot(role: Role.admin);
      website.broken = true;
      await state.restore();
      expect(state.jobs, isNotEmpty);
    });

    test('and it recovers when the website comes back', () async {
      final state = boot(role: Role.admin);
      website.broken = true;
      await state.checkForBookings();

      website.broken = false;
      website.bookings = [booking('bk-1')];
      expect(await state.checkForBookings(), 1);
    });
  });

  group('pricing and publishing', () {
    Future<AppState> withBooking({Role role = Role.admin}) async {
      final state = boot(role: role);
      website.bookings = [booking('bk-1')];
      await state.checkForBookings();
      return state;
    }

    test('an unpriced job is refused, and says why', () async {
      final state = await withBooking();
      final ok = await state.publishJob(state.requestedJobs.single);

      expect(ok, isFalse);
      expect(state.toast, contains("driver's cut"));
      expect(state.requestedJobs, hasLength(1));
    });

    test('a priced one goes to the crew', () async {
      final state = await withBooking();
      await state.editJob(state.requestedJobs.single, {
        'payout': 180,
        'billed': 360,
        'equipment': 'Dump trailer 14k',
        'miles': 22,
      });

      expect(await state.publishJob(state.requestedJobs.single), isTrue);
      expect(state.requestedJobs, isEmpty);
      expect(state.openBoard.map((j) => j.bookingId), contains('bk-1'));
    });

    test('only an owner may publish', () async {
      final state = await withBooking(role: Role.manager);
      final ok = await state.publishJob(state.requestedJobs.single);
      expect(ok, isFalse);
      expect(state.toast, contains('Only an owner'));
    });

    test('the mutation refuses an unpriced publish on replay too', () {
      final job = booking('bk-1').toJob('HL-9001');
      final publish = PublishJob(
        id: 'm1',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
      );

      // The queue outlives the screen that enforced the rule.
      expect(publish.apply(job), isNull);
      final priced = Job.fromJson({...job.toJson(), 'payout': 180});
      expect(publish.apply(priced), isNotNull);
    });

    test('publishing writes itself into the log', () async {
      final state = await withBooking();
      await state.editJob(state.requestedJobs.single, {'payout': 180});
      await state.publishJob(state.requestedJobs.single);

      final job = state.jobs.firstWhere((j) => j.bookingId == 'bk-1');
      expect(job.events.first.label, 'Booked on the website');
      expect(job.events.last.label, contains('put on the board'));
    });
  });

  group('the wire contract', () {
    test('round-trips', () {
      final copy = BookingRequest.fromJson(
        jsonDecode(jsonEncode(booking('bk-1').toJson()))
            as Map<String, Object?>,
      )!;
      expect(copy.id, 'bk-1');
      expect(copy.customer, 'Sunset Ridge Builders');
      expect(copy.details, contains('drywall'));
      expect(copy.requestedAt.toUtc(), DateTime.utc(2026, 8, 4, 9));
    });

    test('a booking with no id is refused', () {
      // Without one it cannot be made idempotent, and anything that cannot be
      // made idempotent is eventually entered twice.
      expect(BookingRequest.fromJson(const {'customer': 'Nobody'}), isNull);
      expect(BookingRequest.fromJson(const {'id': ''}), isNull);
    });

    test('a missing timestamp is not worth refusing a job over', () {
      final b = BookingRequest.fromJson(const {'id': 'bk-1'})!;
      expect(b.requestedAt.millisecondsSinceEpoch, 0);
      expect(b.customer, isEmpty);
    });

    test('an empty booking still produces a usable job', () {
      final job = BookingRequest.fromJson(const {'id': 'bk-1'})!.toJob('HL-1');
      expect(job.type, 'Website booking');
      expect(job.customer, 'Website enquiry');
      expect(job.window, 'Not agreed yet');
      expect(job.status, JobStatus.requested);
    });
  });

  group('the same-origin source', () {
    test('reads what the booking page wrote', () async {
      final store = MemoryStore();
      final source = StoreIntakeSource(store: store);
      await source.add(booking('bk-1'));

      final read = await source.fetch();
      expect(read.single.id, 'bk-1');
      expect(read.single.customer, 'Sunset Ridge Builders');
    });

    test('a half-written file does not take the board down', () async {
      final store = MemoryStore();
      await store.writeString('bookings.v1', '[{"id": "bk-1"');
      expect(await StoreIntakeSource(store: store).fetch(), isEmpty);
    });

    test('an empty store is simply no bookings', () async {
      expect(await StoreIntakeSource(store: MemoryStore()).fetch(), isEmpty);
    });

    test('it drives a real board end to end', () async {
      final store = MemoryStore();
      final source = StoreIntakeSource(store: store);
      await source.add(booking('bk-1'));

      final state = boot(store: store, role: Role.admin, intake: source);
      await state.restore();

      expect(state.requestedJobs.single.bookingId, 'bk-1');
    });
  });

  group('the HTTP source', () {
    HttpIntakeSource source(Future<String?> Function() body) =>
        HttpIntakeSource(
          endpoint: Uri.parse('https://example.test/bookings'),
          get: (_, _) => body(),
        );

    test('reads a bare array', () async {
      final got = await source(
        () async => jsonEncode([booking('bk-1').toJson()]),
      ).fetch();
      expect(got.single.id, 'bk-1');
    });

    test('reads a wrapped one too', () async {
      // Half the world's endpoints wrap their payloads.
      final got = await source(
        () async => jsonEncode({
          'bookings': [booking('bk-1').toJson()],
        }),
      ).fetch();
      expect(got.single.id, 'bk-1');
    });

    test('a dead endpoint yields nothing rather than throwing', () async {
      expect(
        await source(() async => throw StateError('no signal')).fetch(),
        isEmpty,
      );
      expect(await source(() async => null).fetch(), isEmpty);
      expect(await source(() async => 'not json at all').fetch(), isEmpty);
    });
  });

  group('on screen', () {
    testWidgets('a booking shows up for dispatch and not for a driver', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.admin, intake: website);
      website.bookings = [booking('bk-1')];
      await harness.state.checkForBookings();
      harness.state.setTab(HaulTab.jobs);
      await settle(tester);

      expect(find.text('CAME IN FROM THE WEBSITE'), findsOneWidget);
      expect(find.text('NEEDS PRICING'), findsOneWidget);
      expect(find.text('NO PRICE YET'), findsOneWidget);
    });

    testWidgets('a driver never sees it on their board', (tester) async {
      final harness = await pumpApp(
        tester,
        role: Role.employee,
        intake: website,
      );
      website.bookings = [booking('bk-1', customer: 'Website Person')];
      await harness.state.checkForBookings();
      await settle(tester);

      expect(find.text('Website Person'), findsNothing);
    });

    testWidgets('putting it on the board needs a price first', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin, intake: website);
      website.bookings = [booking('bk-1')];
      await harness.state.checkForBookings();
      harness.state.setTab(HaulTab.jobs);
      await settle(tester);

      await tapVisible(tester, find.text('PUT ON THE BOARD'));
      await settle(tester);

      // A dead grey button explains nothing; this one says what is missing.
      expect(harness.state.requestedJobs, hasLength(1));
      expect(find.textContaining("driver's cut"), findsWidgets);
    });
  });
}
