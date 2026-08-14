import 'package:flutter/material.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_theme.dart';
import 'form_bits.dart';

/// Opens the pricing form over the calendar.
///
/// Its own screen rather than a section of the job editor, because it is its
/// own job and its own permission: a manager prices work all day without ever
/// being the person who moves it to Thursday.
Future<bool> showPriceSheet(BuildContext context, Job job) async {
  final app = AppScope.read(context);
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AppScope(
        state: app,
        child: PriceSheet(job: job),
      ),
    ),
  );
  return saved ?? false;
}

/// The boxes on this form, named so a test can reach one without counting
/// text fields down the screen — a count that breaks the first time a row is
/// added, as it did.
const Key kBilledField = Key('billed-field');
const Key kDumpFeeField = Key('dump-fee-field');
const Key kPaidField = Key('paid-field');
const Key kPaymentField = Key('payment-field');

class PriceSheet extends StatefulWidget {
  const PriceSheet({super.key, required this.job});

  final Job job;

  @override
  State<PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<PriceSheet> {
  late final TextEditingController _billed;
  late final TextEditingController _dumpFee;
  late final TextEditingController _paid;
  late final TextEditingController _method;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Zero shows as an empty box, not as "0". A job nobody has priced has no
    // price, and writing a nought in the field says somebody decided on one.
    _billed = TextEditingController(
      text: widget.job.billed == 0 ? '' : '${widget.job.billed}',
    );
    _dumpFee = TextEditingController(
      text: widget.job.dumpFee == 0 ? '' : '${widget.job.dumpFee}',
    );
    _paid = TextEditingController(
      text: widget.job.paid == 0 ? '' : '${widget.job.paid}',
    );
    _method = TextEditingController(text: widget.job.paymentMethod);
    for (final c in [_billed, _dumpFee, _paid, _method]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _billed.dispose();
    _dumpFee.dispose();
    _paid.dispose();
    _method.dispose();
    super.dispose();
  }

  int get _bills => dollarsFrom(_billed.text);
  int get _tip => dollarsFrom(_dumpFee.text);

  /// What is left after the tip, before anybody's hours come out of it.
  int get _before => _bills - _tip;

  int get _taken => dollarsFrom(_paid.text);

  /// What the customer is still short. The figure the day sheet adds up.
  int get _owed => _bills - _taken;

  Future<void> _save({bool andPublish = false}) async {
    setState(() => _saving = true);
    final app = AppScope.read(context);

    await app.priceJob(widget.job, billed: _bills, dumpFee: _tip);
    await app.recordPayment(widget.job, paid: _taken, method: _method.text);
    // Read the job back off the board: publishing checks the price, and the
    // copy this screen was opened with still carries the old one.
    if (andPublish) {
      final fresh = app.jobs.firstWhere(
        (j) => j.id == widget.job.id,
        orElse: () => widget.job,
      );
      await app.publishJob(fresh);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final job = widget.job;
    final unpriced = job.needsPricing;

    return Scaffold(
      backgroundColor: p.groupedBg,
      appBar: AppBar(
        backgroundColor: p.groupedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: t.body.copyWith(color: p.accent)),
        ),
        leadingWidth: 88,
        centerTitle: true,
        title: Text('Price', style: t.navTitle),
        actions: [
          Semantics(
            button: true,
            label: 'Save the price',
            onTap: _saving ? null : _save,
            excludeSemantics: true,
            child: TextButton(
              onPressed: _saving ? null : () => _save(),
              child: Text(
                'Done',
                style: t.bodyStrong.copyWith(
                  color: _saving ? p.tertiaryLabel : p.accent,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              job.customer,
              style: t.largeTitle.copyWith(fontSize: 24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text('${job.type} · ${job.id}', style: t.secondary),
          ),
          FormGroup(
            children: [
              FormRow(
                key: kBilledField,
                label: 'Bills at',
                controller: _billed,
                hint: 'What the customer pays',
                prefix: '\$',
                keyboard: TextInputType.number,
                autofocus: true,
              ),
              FormRow(
                key: kDumpFeeField,
                label: 'Disposal',
                controller: _dumpFee,
                hint: 'What the tip charges',
                prefix: '\$',
                keyboard: TextInputType.number,
              ),
            ],
          ),
          // The arithmetic said out loud. Somebody quoting over the phone is
          // working out whether the job is worth doing, and the disposal fee
          // is the half of that they forget.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text('Before labour', style: t.secondary),
                    ),
                    Expanded(
                      child: Text(
                        _bills == 0
                            ? 'Nothing yet'
                            : '\$$_before after the tip',
                        style: t.body.copyWith(
                          fontSize: 15,
                          color: _before < 0 ? p.accent : p.label,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_before < 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: Text(
                'The tip costs more than the job bills. That can be right for '
                'a favour, but it is worth a second look.',
                textAlign: TextAlign.center,
                style: t.secondary.copyWith(fontSize: 13),
              ),
            ),
          FormGroup(
            children: [
              FormRow(
                key: kPaidField,
                label: 'Paid',
                controller: _paid,
                hint: 'What has been handed over',
                prefix: '\$',
                keyboard: TextInputType.number,
              ),
              // Free text with what the board has taken before offered, the
              // same as the rigs: a yard that starts taking one more kind of
              // payment should not need a new build to write it down.
              _HowPaid(controller: _method, onChanged: () => setState(() {})),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text('Still owes', style: t.secondary),
                    ),
                    Expanded(
                      child: Text(
                        _owed == 0 ? 'Nothing' : '\$$_owed',
                        style: t.bodyStrong.copyWith(
                          fontSize: 15,
                          color: _owed > 0 ? p.accent : p.label,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (unpriced)
            _PutItOnTheBoard(
              enabled: _bills > 0 && !_saving,
              onGo: () => _save(andPublish: true),
            ),
        ],
      ),
    );
  }
}

/// Pricing and publishing in one press, for a booking off the website.
///
/// The two go together in practice — a job is priced *so that* it can go to
/// the crew — and making somebody save, close, reopen and press a second
/// button is how a board ends up full of priced work nobody was offered.
class _PutItOnTheBoard extends StatelessWidget {
  const _PutItOnTheBoard({required this.enabled, required this.onGo});

  final bool enabled;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label:
                'Price it and put it on the board. '
                'The crew cannot take a job on until it has a price.',
            onTap: enabled ? onGo : null,
            excludeSemantics: true,
            child: FilledButton(
              onPressed: enabled ? onGo : null,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                disabledBackgroundColor: p.fill,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                'Put it on the board',
                style: t.bodyStrong.copyWith(
                  fontSize: 16,
                  color: enabled ? p.onAccent : p.tertiaryLabel,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              'The crew cannot take a job on until it has a price.',
              textAlign: TextAlign.center,
              style: t.secondary.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the job was settled — picked off what the board has taken before, or
/// typed when it is something new.
class _HowPaid extends StatelessWidget {
  const _HowPaid({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final known = AppScope.of(context).knownPayments;
    final typed = controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (known.isNotEmpty)
          ChoiceRow<String>(
            label: 'Paid by',
            shown: typed.isEmpty ? 'Not yet' : typed,
            valueColour: typed.isEmpty ? p.tertiaryLabel : null,
            ticked: (way) => way.toLowerCase() == typed.toLowerCase(),
            choices: [for (final way in known) (way, way)],
            onChanged: (way) {
              // Picking the one already on the job clears it, the way tapping
              // a chosen rig takes it off. A payment recorded by mistake has
              // to be undoable without retyping the whole row.
              controller.text = way.toLowerCase() == typed.toLowerCase()
                  ? ''
                  : way;
              onChanged();
            },
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, known.isEmpty ? 8 : 0, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(known.isEmpty ? 'Paid by' : '', style: t.secondary),
              ),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'How it was paid',
                  child: TextField(
                    key: kPaymentField,
                    controller: controller,
                    style: t.body.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: known.isEmpty
                          ? 'Cash, card, a cheque, an invoice'
                          : 'Something else',
                      hintStyle: t.body.copyWith(
                        fontSize: 15,
                        color: p.tertiaryLabel,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
