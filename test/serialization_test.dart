import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/ids.dart';
import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/models/crew_member.dart';
import 'package:haul_board/models/job.dart';

/// Everything the board persists or sends has to survive a round trip through
/// JSON unchanged. These are the tests that stop a sync bug from being a data
/// loss bug.
void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  /// Through a real encode/decode, not just the maps — that is where a
  /// non-encodable value (a DateTime, an enum) actually blows up.
  Job roundTrip(Job job, {Map<String, Uint8List> photos = const {}}) {
    final text = jsonEncode(job.toJson());
    return Job.fromJson(
      jsonDecode(text) as Map<String, Object?>,
      photoBytes: photos,
    );
  }

  group('job round trip', () {
    test('every field of a seeded job survives', () {
      for (final original in kSeedJobs) {
        final copy = roundTrip(original);

        expect(copy.id, original.id);
        expect(copy.type, original.type);
        expect(copy.customer, original.customer);
        expect(copy.address, original.address);
        expect(copy.city, original.city);
        expect(copy.contact, original.contact);
        expect(copy.phone, original.phone);
        expect(copy.access, original.access);
        expect(copy.material, original.material);
        expect(copy.volume, original.volume);
        expect(copy.weight, original.weight);
        expect(copy.equipment, original.equipment);
        expect(copy.disposal, original.disposal);
        expect(copy.dumpFee, original.dumpFee);
        expect(copy.window, original.window);
        expect(copy.miles, original.miles);
        expect(copy.deadhead, original.deadhead);
        expect(copy.payout, original.payout);
        expect(copy.billed, original.billed);
        expect(copy.hazards, original.hazards);
        expect(copy.status, original.status);
        expect(copy.assignedTo, original.assignedTo);
        expect(copy.stage, original.stage);
        expect(copy.progress, closeTo(original.progress, 1e-9));
      }
    });

    test('the movement log keeps its order, wording and moments', () {
      final original = kSeedJobs.firstWhere((j) => j.events.length > 3);
      final copy = roundTrip(original);

      expect(copy.events.length, original.events.length);
      for (var i = 0; i < original.events.length; i++) {
        expect(copy.events[i].label, original.events[i].label);
        expect(copy.events[i].kind, original.events[i].kind);
        // To the second: the wire format is ISO-8601, not a clock string.
        expect(
          copy.events[i].at.difference(original.events[i].at).inSeconds,
          0,
        );
        expect(copy.events[i].time, original.events[i].time);
      }
    });

    test('an event keeps its moment across a timezone change', () {
      final utcNoon = DateTime.utc(2026, 8, 2, 12, 30);
      final event = JobEvent(
        at: utcNoon,
        label: 'Arrived on site',
        kind: EventKind.arrive,
      );
      final copy = JobEvent.fromJson(
        jsonDecode(jsonEncode(event.toJson())) as Map<String, Object?>,
      );
      expect(copy.at.toUtc(), utcNoon);
    });
  });

  group('photos travel separately from the board', () {
    final photo = JobPhoto(
      id: 'photo-1',
      name: 'before.jpg',
      bytes: bytes('the pixels'),
    );

    test('the board JSON carries the record but never the pixels', () {
      final job = kSeedJobs.first.copyWith(photoBefore: photo);
      final text = jsonEncode(job.toJson());

      expect(text, contains('photo-1'));
      expect(text, contains('before.jpg'));
      // A board is rewritten on every change; inlining megabytes of image
      // would make that write cost grow without bound.
      expect(text, isNot(contains('the pixels')));
    });

    test('pixels are reattached by id on the way back', () {
      final job = kSeedJobs.first.copyWith(photoBefore: photo);
      final copy = roundTrip(job, photos: {'photo-1': bytes('the pixels')});

      expect(copy.photoBefore, isNotNull);
      expect(copy.photoBefore!.id, 'photo-1');
      expect(copy.photoBefore!.name, 'before.jpg');
      expect(utf8.decode(copy.photoBefore!.bytes), 'the pixels');
    });

    test('a photo whose pixels are missing is dropped, not faked', () {
      final job = kSeedJobs.first.copyWith(photoBefore: photo);
      final copy = roundTrip(job); // no bytes supplied

      // Better to show the driver an empty slot they can refill than a
      // photo record that cannot be displayed or uploaded.
      expect(copy.photoBefore, isNull);
      expect(copy.photosComplete, isFalse);
    });

    test('an uploaded photo remembers where it landed', () {
      final uploaded = photo.copyWith(remoteUrl: 'https://example.test/p1.jpg');
      expect(uploaded.uploaded, isTrue);

      final copy = roundTrip(
        kSeedJobs.first.copyWith(photoAfter: uploaded),
        photos: {'photo-1': bytes('the pixels')},
      );
      expect(copy.photoAfter!.remoteUrl, 'https://example.test/p1.jpg');
      expect(photo.uploaded, isFalse, reason: 'the original is untouched');
    });
  });

  group('crew round trip', () {
    test('every seeded driver survives', () {
      for (final original in kCrew) {
        final copy = CrewMember.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
        );
        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.initials, original.initials);
        expect(copy.unit, original.unit);
        expect(copy.onShift, original.onShift);
        expect(copy.appOpen, original.appOpen);
        expect(copy.rig, original.rig);
        expect(copy.lastSeen, original.lastSeen);
        expect(copy.lastPlace, original.lastPlace);
      }
    });
  });

  group('malformed input degrades instead of throwing', () {
    // A board written by a newer build, or a half-written file, must not
    // brick the app on launch — the driver still has a shift to run.
    test('an empty object yields a usable job', () {
      final job = Job.fromJson(const {});
      expect(job.status, JobStatus.open);
      expect(job.stage, 0);
      expect(job.events, isEmpty);
      expect(job.progress, 0);
    });

    test('an unknown status falls back to open', () {
      final job = Job.fromJson(const {'status': 'teleported'});
      expect(job.status, JobStatus.open);
    });

    test('an unknown event kind falls back to a plain line', () {
      final event = JobEvent.fromJson(const {'kind': 'exploded', 'at': 'nope'});
      expect(event.kind, EventKind.flat);
    });

    test('an out-of-range stage is clamped rather than crashing the rail', () {
      expect(Job.fromJson(const {'stage': 99}).stage, kStages.length - 1);
      expect(Job.fromJson(const {'stage': -4}).stage, 0);
    });

    test('progress outside 0..1 is clamped', () {
      expect(Job.fromJson(const {'progress': 4.2}).progress, 1.0);
      expect(Job.fromJson(const {'progress': -1}).progress, 0.0);
    });
  });

  group('device-minted ids', () {
    test('are unique across a burst', () {
      final generator = IdGenerator();
      final seen = {for (var i = 0; i < 5000; i++) generator.next('photo')};
      expect(seen.length, 5000);
    });

    test('carry their prefix and sort by time', () {
      var tick = DateTime.utc(2026, 1, 1);
      final generator = IdGenerator(
        now: () => tick = tick.add(const Duration(seconds: 1)),
      );
      final first = generator.next('photo');
      final second = generator.next('photo');

      expect(first, startsWith('photo-'));
      expect(first.compareTo(second), lessThan(0));
    });
  });
}
