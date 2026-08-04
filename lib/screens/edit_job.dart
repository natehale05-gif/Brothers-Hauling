import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import '../widgets/primitives.dart';

/// One editable field, described once so the form, the diff and the tests all
/// read from the same place.
class _Field {
  const _Field(
    this.key,
    this.label, {
    this.hint,
    this.helper,
    this.number = false,
    this.money = false,
    this.date = false,
    this.lines = 1,
  });

  final String key;
  final String label;
  final String? hint;
  final String? helper;
  final bool number;
  final bool money;

  /// A calendar day, written as YYYY-MM-DD. Blank means no day set — which is
  /// a real answer for a booking nobody has committed to yet, not an error.
  final bool date;
  final int lines;
}

/// The date half of a timestamp, as the form writes it.
///
/// Compared date-to-date rather than string-to-string, because the stored value
/// is a full ISO timestamp — comparing that against "2026-08-05" would report a
/// change every time the form was opened and closed.
String _asDate(Object? value) {
  final parsed = DateTime.tryParse('${value ?? ''}')?.toLocal();
  if (parsed == null) return '';
  final m = parsed.month.toString().padLeft(2, '0');
  final d = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$m-$d';
}

const _sections = <String, List<_Field>>{
  'The customer': [
    _Field('type', 'Job type', hint: 'Debris haul'),
    _Field('customer', 'Customer', hint: 'Sunset Ridge Builders'),
    _Field('contact', 'Contact', hint: 'Marla'),
    _Field('phone', 'Phone', hint: '555-0142'),
  ],
  'Where': [
    _Field('address', 'Address', hint: '1180 Decker Rd'),
    _Field('city', 'City', hint: 'Philomath'),
    _Field(
      'access',
      'Access notes',
      lines: 3,
      helper: 'What the driver needs to know before they turn up.',
    ),
    _Field(
      'hazards',
      'Hazards',
      lines: 3,
      helper: 'One per line. These are called out in red on the job card.',
    ),
  ],
  'The load': [
    _Field('material', 'Material', hint: 'Mixed construction debris'),
    _Field('volume', 'Volume', hint: '6 yd'),
    _Field('weight', 'Weight', hint: '~4,200 lb'),
    _Field('equipment', 'Equipment', hint: 'Dump trailer 14k'),
    _Field(
      'disposal',
      'Goes to',
      hint: 'Coffin Butte Landfill',
      helper: 'Start with "N/A" when there is no disposal stop.',
    ),
  ],
  'Timing and distance': [
    _Field(
      'scheduledFor',
      'Day',
      hint: '2026-08-05',
      date: true,
      helper:
          'YYYY-MM-DD. Leave it blank if no day is agreed yet — the day '
          'view keeps it in its own bucket rather than guessing.',
    ),
    _Field('window', 'Time window', hint: '7:00 – 9:00 AM'),
    _Field('miles', 'Loaded miles', number: true),
    _Field('deadhead', 'Deadhead miles', number: true),
  ],
  'Money': [
    // No driver's cut: pay is hourly, and hours are not a property of a job.
    _Field('billed', 'Bills at', number: true, money: true),
    _Field('dumpFee', 'Disposal fee', number: true, money: true),
  ],
};

Future<void> showEditJobSheet(BuildContext context, Job job) {
  final state = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AppScope(
      state: state,
      child: EditJobForm(job: job),
    ),
  );
}

/// Every detail of a job, in one form.
///
/// Only the fields dispatch owns. The stage, the photos, the assignee and the
/// movement log are the record of what happened in the field, and this is not
/// the place to rewrite it.
class EditJobForm extends StatefulWidget {
  const EditJobForm({super.key, required this.job});

  final Job job;

  @override
  State<EditJobForm> createState() => _EditJobFormState();
}

class _EditJobFormState extends State<EditJobForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final field in _sections.values.expand((f) => f))
      field.key: TextEditingController(text: _initial(field)),
  };

  String _initial(_Field field) {
    final value = widget.job.toJson()[field.key];
    if (field.key == 'hazards') {
      return (value as List?)?.cast<String>().join('\n') ?? '';
    }
    if (field.date) return _asDate(value);
    return '${value ?? ''}';
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only what actually changed. An edit that names every field would clobber
  /// anything the driver changed on the same job while this form was open.
  Map<String, Object?> _changes() {
    final before = widget.job.toJson();
    final out = <String, Object?>{};

    for (final field in _sections.values.expand((f) => f)) {
      final text = _controllers[field.key]!.text.trim();

      final Object? value;
      if (field.key == 'hazards') {
        value = [
          for (final line in text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ];
      } else if (field.number) {
        value = int.tryParse(text) ?? 0;
      } else if (field.date) {
        // Blank clears the day. Anything unparseable never gets this far —
        // the validator stops it.
        value = DateTime.tryParse(text)?.toIso8601String();
      } else {
        value = text;
      }

      if (field.date) {
        if (_asDate(before[field.key]) != text) out[field.key] = value;
      } else if (field.key == 'hazards') {
        final was = (before[field.key] as List?)?.cast<String>() ?? const [];
        final now = value as List<String>;
        if (was.length != now.length ||
            List.generate(was.length, (i) => was[i] != now[i]).any((x) => x)) {
          out[field.key] = now;
        }
      } else if (before[field.key] != value) {
        out[field.key] = value;
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = AppScope.of(context);
    final changes = _changes();

    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    await state.editJob(widget.job, changes);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);

    return AlertDialog(
      backgroundColor: hc.surface,
      title: Text('Edit ${widget.job.id}', style: ht.heading),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in _sections.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: Semantics(
                      header: true,
                      child: Text(
                        section.key.toUpperCase(),
                        style: ht.blockTitle,
                      ),
                    ),
                  ),
                  for (final field in section.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: HaulTextField(
                        controller: _controllers[field.key]!,
                        label: field.label,
                        hint: field.hint,
                        helper: field.helper,
                        maxLines: field.lines,
                        prefix: field.money ? r'$' : null,
                        keyboardType: field.number
                            ? TextInputType.number
                            : (field.lines > 1
                                  ? TextInputType.multiline
                                  : TextInputType.text),
                        inputFormatters: field.number
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : null,
                        validator: switch (field) {
                          _Field(number: true) => (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) return 'Enter a number, or 0.';
                            return int.tryParse(text) == null
                                ? 'Whole numbers only.'
                                : null;
                          },
                          _Field(date: true) => (v) {
                            final text = (v ?? '').trim();
                            // Blank is a real answer — no day agreed yet.
                            if (text.isEmpty) return null;
                            return DateTime.tryParse(text) == null
                                ? 'Write the day as YYYY-MM-DD, or leave it '
                                      'blank.'
                                : null;
                          },
                          _ => null,
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: ht.action.copyWith(fontSize: 13, color: hc.inkSoft),
          ),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: hc.brand,
            foregroundColor: hc.onBrand,
            minimumSize: const Size(0, HaulSpace.tap),
          ),
          child: Text(
            'SAVE CHANGES',
            style: ht.action.copyWith(fontSize: 12, color: hc.onBrand),
          ),
        ),
      ],
    );
  }
}
