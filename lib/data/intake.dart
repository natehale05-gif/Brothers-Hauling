import 'dart:async';
import 'dart:convert';

import '../models/job.dart';
import 'store.dart';

/// A job someone asked for on the website.
///
/// This is the wire contract between brothershauling.com and the board, and it
/// is deliberately small: a customer filling in a form knows what they want
/// moved and where from, and knows none of the things the app needs to run the
/// job. Everything else — mileage, equipment, what it pays — is dispatch's to
/// fill in afterwards, which is why a booking arrives as
/// [JobStatus.requested] rather than straight onto the driver board.
///
/// The JSON a website should POST (or write) looks like:
///
/// ```json
/// {
///   "id": "bk_01H8...",
///   "requestedAt": "2026-08-04T15:04:05Z",
///   "customer": "Sunset Ridge Builders",
///   "contact": "Marla",
///   "phone": "555-0142",
///   "address": "1180 Decker Rd",
///   "city": "Philomath",
///   "type": "Debris haul",
///   "details": "Two pallets of broken drywall behind the garage.",
///   "window": "Weekday mornings"
/// }
/// ```
///
/// Only `id` is structurally required. A booking with no id cannot be made
/// idempotent, and a booking that cannot be made idempotent will eventually be
/// entered twice.
class BookingRequest {
  const BookingRequest({
    required this.id,
    required this.requestedAt,
    this.customer = '',
    this.contact = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.type = '',
    this.details = '',
    this.window = '',
  });

  /// The website's id for this booking, and the thing that stops it being
  /// entered twice.
  final String id;

  final DateTime requestedAt;
  final String customer;
  final String contact;
  final String phone;
  final String address;
  final String city;
  final String type;

  /// Whatever the customer typed into the box. Goes into the access notes,
  /// where the driver reads it, rather than being thrown away.
  final String details;

  /// What the customer asked for, in their words — "weekday mornings", not a
  /// slot the office has agreed to.
  final String window;

  static BookingRequest? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;

    String text(String key) => (json[key] as String? ?? '').trim();

    return BookingRequest(
      id: id,
      // A missing or unparseable timestamp is not worth refusing the job over;
      // the booking still happened.
      requestedAt:
          DateTime.tryParse(json['requestedAt'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      customer: text('customer'),
      contact: text('contact'),
      phone: text('phone'),
      address: text('address'),
      city: text('city'),
      type: text('type'),
      details: text('details'),
      window: text('window'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'customer': customer,
    'contact': contact,
    'phone': phone,
    'address': address,
    'city': city,
    'type': type,
    'details': details,
    'window': window,
  };

  /// Turns the booking into a job dispatch can work with.
  ///
  /// Everything the customer could not know is left blank or zero rather than
  /// guessed. A made-up mileage or an invented payout would look exactly like a
  /// real one on the board, which is worse than an obviously empty field.
  Job toJob(String jobId) => Job(
    id: jobId,
    bookingId: id,
    status: JobStatus.requested,
    type: type.isEmpty ? 'Website booking' : type,
    customer: customer.isEmpty ? 'Website enquiry' : customer,
    address: address,
    city: city,
    contact: contact,
    phone: phone,
    access: details,
    material: '',
    volume: '',
    weight: '',
    equipment: '',
    disposal: 'N/A — not set',
    dumpFee: 0,
    window: window.isEmpty ? 'Not agreed yet' : window,
    miles: 0,
    deadhead: 0,
    payout: 0,
    billed: 0,
    events: [
      JobEvent(
        at: requestedAt,
        label: 'Booked on the website',
        kind: EventKind.flat,
      ),
    ],
  );
}

/// Where bookings come from.
///
/// An interface for the same reason the location and photo services are: the
/// app should not know whether a booking arrived over HTTP from a real backend
/// or out of the browser's own storage on a static demo. Both are polled the
/// same way, and neither is allowed to take the board down by failing.
abstract class IntakeSource {
  /// Everything the source currently knows about.
  ///
  /// Returning the full set rather than "what is new" is deliberate — the
  /// caller dedupes by booking id anyway, and a source that has to remember
  /// what it already handed over is a source that loses a booking whenever the
  /// app dies at the wrong moment.
  Future<List<BookingRequest>> fetch();
}

/// No website wired up. The board still works.
class NoIntakeSource implements IntakeSource {
  const NoIntakeSource();

  @override
  Future<List<BookingRequest>> fetch() async => const [];
}

/// Reads bookings a same-origin page has written into device storage.
///
/// This is what makes the hosted demo real: `hire.html` is served from the same
/// origin as the app, so a booking made there lands in the same browser storage
/// the board reads. No server, but a genuine round trip rather than a mocked
/// one — and the seam is identical to the HTTP one, so pointing the app at a
/// real backend changes which class is constructed and nothing else.
class StoreIntakeSource implements IntakeSource {
  const StoreIntakeSource({required this.store, this.key = 'bookings.v1'});

  final Store store;
  final String key;

  @override
  Future<List<BookingRequest>> fetch() async {
    final text = await store.readString(key);
    if (text == null) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return [
        for (final raw in decoded.whereType<Map>())
          ?BookingRequest.fromJson(raw.cast<String, Object?>()),
      ];
    } on FormatException {
      // A half-written booking file is not worth taking the board down for.
      return const [];
    }
  }

  /// Used by the demo page and the tests to file a booking.
  Future<void> add(BookingRequest booking) async {
    final existing = await fetch();
    final next = [
      for (final b in existing)
        if (b.id != booking.id) b,
      booking,
    ];
    await store.writeString(
      key,
      jsonEncode([for (final b in next) b.toJson()]),
    );
  }
}

/// Polls a real backend.
///
/// The endpoint returns the JSON array documented on [BookingRequest]. A
/// failure — no signal, a 500, a truncated body — yields nothing rather than
/// throwing: the board is not allowed to break because the website is down.
class HttpIntakeSource implements IntakeSource {
  const HttpIntakeSource({
    required this.endpoint,
    required this.get,
    this.headers = const {},
  });

  final Uri endpoint;
  final Map<String, String> headers;

  /// Injected rather than importing a client, so this stays testable and the
  /// app keeps its "no dependency that can break a Windows build" rule.
  final Future<String?> Function(Uri url, Map<String, String> headers) get;

  @override
  Future<List<BookingRequest>> fetch() async {
    final String? body;
    try {
      body = await get(endpoint, headers);
    } catch (_) {
      return const [];
    }
    if (body == null) return const [];

    try {
      final decoded = jsonDecode(body);
      final list = switch (decoded) {
        final List l => l,
        // Tolerates {"bookings": [...]} as well as a bare array, because half
        // the world's endpoints wrap their payloads.
        final Map m when m['bookings'] is List => m['bookings']! as List,
        _ => const [],
      };
      return [
        for (final raw in list.whereType<Map>())
          ?BookingRequest.fromJson(raw.cast<String, Object?>()),
      ];
    } on FormatException {
      return const [];
    }
  }
}
