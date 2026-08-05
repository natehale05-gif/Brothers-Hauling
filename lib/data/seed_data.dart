import '../models/crew_member.dart';
import '../models/job.dart';

/// The signed-in driver. A real build would resolve this from auth.
const String kMeId = 'c1';

const List<CrewMember> kCrew = [
  CrewMember(
    id: 'c1',
    name: 'Nate R.',
    initials: 'NR',
    unit: 'Unit 12',
    onShift: true,
    appOpen: true,
  ),
  CrewMember(
    id: 'c2',
    name: 'D. Alvarez',
    initials: 'DA',
    unit: 'Unit 04',
    onShift: true,
    appOpen: true,
  ),
  CrewMember(
    id: 'c3',
    name: 'K. Whitlow',
    initials: 'KW',
    unit: 'Unit 07',
    onShift: true,
    appOpen: false,
    lastSeen: '8:02 AM',
    lastPlace: 'Hwy 20 near Philomath',
  ),
  CrewMember(
    id: 'c4',
    name: 'M. Sood',
    initials: 'MS',
    unit: 'Unit 09',
    onShift: false,
    appOpen: false,
    lastSeen: 'Yesterday 4:40 PM',
    lastPlace: 'Yard',
  ),
];

CrewMember? crewById(String? id) {
  if (id == null) return null;
  for (final c in kCrew) {
    if (c.id == id) return c;
  }
  return null;
}

/// A time on the current day, so the demo board reads as "today" whenever it
/// is opened rather than being pinned to the date it was written.
DateTime _today(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// A day relative to [from], at a given hour. The seed spreads across a few
/// days so the day view has something to swipe through on a fresh install.
DateTime _day(DateTime from, int offset, [int hour = 8]) =>
    DateTime(from.year, from.month, from.day + offset, hour);

/// Today's board.
///
/// No longer `const`: events carry real [DateTime]s now, and Dart has no const
/// DateTime. Built once at startup.
List<Job> seedJobs(DateTime now) => [
  Job(
    id: 'HL-4471',
    scheduledFor: _day(now, 0, 7),
    type: 'Debris haul',
    customer: 'Sunset Ridge Builders',
    address: '3820 NW Sunset Ridge Dr',
    city: 'Philomath',
    contact: 'Ray Tilden',
    phone: '541-555-0148',
    access:
        'Enter from the gravel spur, not the main drive. Gate code 4417#. '
        'Dogs on site — call ahead.',
    material: 'Construction debris — framing offcuts, drywall',
    volume: '6 yd',
    weight: '~4,200 lb',
    equipment: 'Dump trailer 14k',
    disposal: 'Coffin Butte Landfill',
    dumpFee: 62,
    window: '7:00 – 9:00 AM',
    miles: 22,
    deadhead: 6,
    billed: 395,
    hazards: ['Exposed nails in the pile', 'Soft ground near the pad'],
  ),
  Job(
    id: 'HL-4482',
    scheduledFor: _day(now, 0, 11),
    type: 'Gravel delivery',
    customer: 'Decker Rd residence',
    address: '18775 Decker Rd',
    city: 'Blodgett',
    contact: 'Jean Prosser',
    phone: '541-555-0192',
    access:
        'Long single-lane drive. Turn around at the top by the barn — '
        'do not back down.',
    material: '3/4-minus crushed rock',
    volume: '8 yd',
    weight: '~11,000 lb',
    equipment: 'Dump trailer 14k',
    disposal: 'N/A — delivery',
    dumpFee: 0,
    window: 'Before 11:00 AM',
    miles: 31,
    deadhead: 9,
    billed: 540,
    hazards: ['Overhead power line at the gate — 14 ft clearance'],
  ),
  Job(
    id: 'HL-4488',
    scheduledFor: _day(now, 1, 13),
    type: 'Equipment move',
    customer: 'Ash Creek Farm',
    address: '9040 Airlie Rd',
    city: 'Monmouth',
    contact: 'Owen Barta',
    phone: '541-555-0110',
    access:
        'Load at Willamette Rentals in Albany first. Ask for the yard '
        'manager.',
    material: 'Mini excavator — Kubota KX040',
    volume: '1 unit',
    weight: '8,600 lb',
    equipment: 'Lowboy 25t',
    disposal: 'N/A — transport',
    dumpFee: 0,
    window: '1:00 – 4:00 PM',
    miles: 27,
    deadhead: 14,
    billed: 690,
    hazards: ['Chain and binder check required before leaving the yard'],
  ),
  Job(
    id: 'HL-4491',
    scheduledFor: _day(now, 0, 9),
    type: 'Junk removal',
    customer: 'Harrison St rental',
    address: '1420 NW Harrison Blvd',
    city: 'Corvallis',
    contact: 'Property mgr — Lia',
    phone: '541-555-0173',
    access:
        'Park in the alley. Unit is the detached garage, key in lockbox '
        '0913.',
    material: 'Garage cleanout — furniture, boxes, one fridge',
    volume: '3 yd',
    weight: '~900 lb',
    equipment: 'Flatbed 20ft',
    disposal: 'Republic Transfer Station',
    dumpFee: 41,
    window: 'Flexible today',
    miles: 8,
    deadhead: 3,
    billed: 240,
    hazards: ['Fridge must go to appliance bay — freon fee applies'],
    status: JobStatus.assigned,
    assignedTo: kMeId,
  ),
  Job(
    id: 'HL-4495',
    scheduledFor: _day(now, 2, 8),
    type: 'Bark & soil',
    customer: 'Airlie Rd residence',
    address: '22110 Airlie Rd',
    city: 'Monmouth',
    contact: 'Sam Ferro',
    phone: '541-555-0166',
    access: 'Dump on the tarp beside the driveway, not on the gravel.',
    material: 'Fir bark, medium grind',
    volume: '5 yd',
    weight: '~3,000 lb',
    equipment: 'Dump trailer 14k',
    disposal: 'N/A — delivery',
    dumpFee: 0,
    window: '2:00 – 6:00 PM',
    miles: 19,
    deadhead: 11,
    billed: 315,
    status: JobStatus.active,
    assignedTo: 'c2',
    stage: 1,
    progress: 0.42,
    events: [
      JobEvent(
        at: _today(7, 48),
        label: 'Accepted the job',
        kind: EventKind.flat,
      ),
      JobEvent(
        at: _today(7, 55),
        label: 'Left the yard — on the way to Tangent',
        kind: EventKind.depart,
      ),
    ],
  ),
  Job(
    id: 'HL-4468',
    scheduledFor: _day(now, -1, 8),
    type: 'Debris haul',
    customer: 'Timberhill remodel',
    address: '2955 NW Timberhill Pl',
    city: 'Corvallis',
    contact: 'Dana Reyes',
    phone: '541-555-0121',
    access: 'Driveway is steep — back in from the cul-de-sac.',
    material: 'Roofing tear-off',
    volume: '7 yd',
    weight: '~6,800 lb',
    equipment: 'Dump trailer 14k',
    disposal: 'Coffin Butte Landfill',
    dumpFee: 88,
    window: 'Completed 9:40 AM',
    miles: 16,
    deadhead: 5,
    billed: 470,
    status: JobStatus.done,
    assignedTo: 'c3',
    stage: 5,
    progress: 1,
    events: [
      JobEvent(
        at: _today(8, 10),
        label: 'Left the yard — on the way to Corvallis',
        kind: EventKind.depart,
      ),
      JobEvent(
        at: _today(8, 26),
        label: 'Arrived on site',
        kind: EventKind.arrive,
      ),
      JobEvent(
        at: _today(9, 2),
        label: 'Left the site — hauling to Coffin Butte Landfill',
        kind: EventKind.depart,
      ),
      JobEvent(
        at: _today(9, 31),
        label: 'Arrived at Coffin Butte Landfill',
        kind: EventKind.arrive,
      ),
      JobEvent(at: _today(9, 40), label: 'Job closed', kind: EventKind.flat),
    ],
  ),
];
