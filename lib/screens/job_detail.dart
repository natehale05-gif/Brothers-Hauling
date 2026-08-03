import 'package:flutter/material.dart';

import '../data/seed_data.dart';
import '../models/job.dart';
import '../services/link_service.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import '../widgets/event_log.dart';
import '../widgets/primitives.dart';
import '../widgets/stage_rail.dart';

/// The full job card: where, how to get in, what the load is, the movement log,
/// money (dispatch only), and the two photos that gate closing it out.
///
/// Rendered full-screen on a phone and in a side pane on a tablet or desktop —
/// [showCloseButton] is the only difference.
class JobDetail extends StatelessWidget {
  const JobDetail({
    super.key,
    required this.job,
    required this.links,
    this.showCloseButton = true,
  });

  final Job job;
  final LinkService links;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final mineActive =
        job.assignedTo == kMeId && job.status == JobStatus.active;
    final worker = crewById(job.assignedTo);
    final showMoney = state.canSeeMoney;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          job: job,
          showMoney: showMoney,
          showCloseButton: showCloseButton,
          onClose: state.closeJobCard,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
            children: [
              if (job.status == JobStatus.active)
                HaulBlock(
                  title: 'Progress',
                  child: StageRail(stage: job.stage),
                ),

              HaulBlock(
                title: 'Where',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.address, style: ht.bodyStrong),
                          Text('${job.city}, OR', style: ht.body),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    KeyValueRow(label: 'Contact', value: job.contact),
                    KeyValueRow(
                      label: 'Phone',
                      value: job.phone,
                      valueStyle: ht.mono.copyWith(color: hc.ink, fontSize: 14),
                    ),
                    KeyValueRow(
                      label: 'Window',
                      value: job.window,
                      divider: false,
                    ),
                    const SizedBox(height: 12),
                    _NavRow(job: job, links: links),
                    if (job.stage >= 3 && job.hasDisposalStop)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          "You're loaded — this routes to ${job.disposal}, "
                          'not back to the customer.',
                          style: ht.small.copyWith(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              HaulBlock(
                title: 'Access notes',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(job.access, style: ht.body),
                    for (final h in job.hazards) HazardNote(text: h),
                  ],
                ),
              ),

              HaulBlock(
                title: 'The load',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyValueRow(label: 'Material', value: job.material),
                    KeyValueRow(label: 'Volume', value: job.volume),
                    KeyValueRow(label: 'Weight', value: job.weight),
                    KeyValueRow(label: 'Equipment', value: job.equipment),
                    KeyValueRow(
                      label: 'Goes to',
                      value: job.disposal,
                      divider: job.dumpFee > 0,
                    ),
                    if (job.dumpFee > 0)
                      KeyValueRow(
                        label: 'Disposal fee',
                        value: '\$${job.dumpFee} — company card',
                        divider: false,
                      ),
                  ],
                ),
              ),

              if (job.events.isNotEmpty)
                HaulBlock(
                  title: 'Movement log',
                  child: EventLog(events: job.events),
                ),

              if (showMoney) _MoneyAndStaffing(job: job, worker: worker?.name),

              _PhotoBlock(job: job, enabled: mineActive),
            ],
          ),
        ),
        if (mineActive) _AdvanceBar(job: job),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.job,
    required this.showMoney,
    required this.showCloseButton,
    required this.onClose,
  });

  final Job job;
  final bool showMoney;
  final bool showCloseButton;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(bottom: BorderSide(color: hc.line)),
      ),
      child: Row(
        children: [
          if (showCloseButton) ...[
            HaulIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back to the list',
              onPressed: onClose,
            ),
            const SizedBox(width: 10),
          ] else
            const SizedBox(width: 4),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      job.type.toUpperCase(),
                      style: ht.heading.copyWith(fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${job.id} · ${job.customer}', style: ht.mono),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: showMoney
                ? 'Bills at ${job.billed} dollars'
                : 'Your cut, ${job.payout} dollars',
            excludeSemantics: true,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\$${showMoney ? job.billed : job.payout}',
                  style: ht.money.copyWith(fontSize: 18),
                ),
                Text(
                  showMoney ? 'billed' : 'your cut',
                  style: ht.small.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (!showCloseButton) ...[
            const SizedBox(width: 8),
            HaulIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close job card',
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

/// Directions and Call. Wrapped so they stack instead of squeezing when the
/// text is scaled up.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.job, required this.links});

  final Job job;
  final LinkService links;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final target = job.legTarget;
    final toDisposal = job.stage >= 3 && job.hasDisposalStop;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => links.openDirections(target.query),
            icon: const Icon(Icons.place_rounded, size: 17),
            label: Text(
              toDisposal ? 'TO DISPOSAL' : 'DIRECTIONS',
              style: ht.action.copyWith(color: hc.onBrand),
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: hc.brand,
              foregroundColor: hc.onBrand,
              minimumSize: const Size(0, HaulSpace.tap),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => links.call(job.phone),
            icon: const Icon(Icons.phone_rounded, size: 17),
            label: Text(
              'CALL',
              style: ht.action,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: hc.raised,
              foregroundColor: hc.ink,
              minimumSize: const Size(0, HaulSpace.tap),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MoneyAndStaffing extends StatelessWidget {
  const _MoneyAndStaffing({required this.job, required this.worker});

  final Job job;
  final String? worker;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return HaulBlock(
      title: 'Money & staffing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(label: 'Billed to customer', value: '\$${job.billed}'),
          KeyValueRow(label: 'Driver payout', value: '\$${job.payout}'),
          KeyValueRow(label: 'Disposal cost', value: '\$${job.dumpFee}'),
          KeyValueRow(
            label: 'Margin',
            value: '\$${job.margin}',
            valueStyle: ht.bodyStrong.copyWith(color: hc.go),
          ),
          KeyValueRow(
            label: 'Assigned to',
            value: worker ?? 'Nobody yet',
            divider: false,
          ),
          if (job.status == JobStatus.open) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text('PUSH TO A DRIVER', style: ht.blockTitle),
            ),
            const SizedBox(height: 6),
            for (final c in kCrew.where((c) => c.onShift))
              Semantics(
                button: true,
                label:
                    'Push ${job.id} to ${c.name}'
                    '${c.appOpen ? "" : ", app currently closed"}',
                excludeSemantics: true,
                child: TextButton(
                  onPressed: () => state.assign(job, c.id),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(HaulSpace.tap),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: hc.ink,
                  ),
                  child: Row(
                    children: [
                      CrewAvatar.muted(initials: c.initials, size: 30),
                      const SizedBox(width: 10),
                      Expanded(child: Text(c.name, style: ht.bodyStrong)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Pill(label: c.appOpen ? 'Assign' : 'Offline'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PhotoBlock extends StatelessWidget {
  const _PhotoBlock({required this.job, required this.enabled});

  final Job job;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return HaulBlock(
      title: 'Before / after photos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PhotoSlot(
                  slot: 'before',
                  photo: job.photoBefore,
                  enabled: enabled,
                  onPick: () => state.addPhoto(job, before: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoSlot(
                  slot: 'after',
                  photo: job.photoAfter,
                  enabled: enabled,
                  onPick: () => state.addPhoto(job, before: false),
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            Text(
              job.photosComplete
                  ? 'Both photos in — you can close this job.'
                  : 'Both photos are required before this job can close.',
              style: ht.small.copyWith(
                fontSize: 12,
                color: job.photosComplete ? hc.go : hc.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.slot,
    required this.photo,
    required this.enabled,
    required this.onPick,
  });

  final String slot;
  final JobPhoto? photo;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final filled = photo != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: filled
          ? '$slot photo, filed. Activate to replace it.'
          : enabled
          ? 'Add the $slot photo'
          : '$slot photo — you are not on this job',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: hc.raised,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPick : null,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: filled ? hc.go : hc.line, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: filled
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          photo!.bytes,
                          fit: BoxFit.cover,
                          // Described by the Semantics wrapper above.
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: hc.raised,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: hc.inkSoft,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 7,
                          top: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: hc.bg.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              slot.toUpperCase(),
                              style: ht.eyebrow.copyWith(
                                color: hc.ink,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 7,
                          top: 7,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: hc.go,
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: hc.bg,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 24,
                          color: enabled ? hc.ink : hc.inkSoft,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slot.toUpperCase(),
                          style: ht.action.copyWith(
                            fontSize: 12,
                            color: enabled ? hc.ink : hc.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            enabled ? 'Tap to shoot' : 'Not on this job',
                            textAlign: TextAlign.center,
                            style: ht.small.copyWith(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one button that walks a job forward. Blocked at the last step until both
/// photos exist, and it says so rather than just greying out.
class _AdvanceBar extends StatelessWidget {
  const _AdvanceBar({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final blocked = job.stage >= 4 && !job.photosComplete;
    final label = blocked ? 'Photos needed to close' : kStageActions[job.stage];

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(top: BorderSide(color: hc.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Semantics(
            button: true,
            enabled: !blocked,
            label: blocked
                ? 'Photos needed to close this job'
                : '$label — moves ${job.id} to the next stage',
            excludeSemantics: true,
            child: FilledButton.icon(
              onPressed: blocked ? null : () => state.advance(job),
              icon: Icon(
                blocked
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
              ),
              label: Text(
                label.toUpperCase(),
                style: ht.action.copyWith(
                  color: blocked
                      ? hc.inkSoft
                      : job.stage >= 4
                      ? hc.bg
                      : hc.ink,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: job.stage >= 4 && !blocked
                    ? hc.brand
                    : hc.raised,
                foregroundColor: job.stage >= 4 && !blocked ? hc.bg : hc.ink,
                disabledBackgroundColor: hc.raised,
                disabledForegroundColor: hc.inkSoft,
                minimumSize: const Size.fromHeight(HaulSpace.tap),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
