import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

import 'onboarding_service.dart';

/// How long a session took, as the end screen says it: "under a minute",
/// "12 min", "1 h 5 min".
String sessionLengthText(Duration d) {
  if (d.inMinutes < 1) return tr('nd-qs-length-short');
  if (d.inMinutes < 60) return tr('nd-qs-length-min', [d.inMinutes]);
  return tr('nd-qs-length-h', [d.inHours, d.inMinutes % 60]);
}

/// What happened in the session, as label and value rows: who helped, how
/// long, and files and messages when there were any.
class SessionSummary extends StatelessWidget {
  const SessionSummary({super.key, required this.state});
  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final helper = (s.supporterName ?? '').trim();
    final length = s.sessionLength;
    return NdFacts(facts: [
      if (helper.isNotEmpty) NdFact(tr('nd-qs-summary-helper'), helper),
      if (length != null)
        NdFact(tr('nd-qs-summary-length'), sessionLengthText(length)),
      if (s.files.isNotEmpty)
        NdFact(tr('nd-qs-summary-files'), '${s.files.length}'),
      if (s.messages.isNotEmpty)
        NdFact(tr('nd-qs-summary-messages'), '${s.messages.length}'),
    ]);
  }
}

/// The console's feedback questions on the end screen. The answers live
/// here until Send; [onChanged] reports them on every change.
class SessionFeedbackForm extends StatefulWidget {
  const SessionFeedbackForm({
    super.key,
    required this.questions,
    required this.onChanged,
    this.enabled = true,
  });

  final List<FeedbackQuestion> questions;
  final ValueChanged<Map<String, Object>> onChanged;
  final bool enabled;

  @override
  State<SessionFeedbackForm> createState() => _SessionFeedbackFormState();
}

class _SessionFeedbackFormState extends State<SessionFeedbackForm> {
  final Map<String, Object> _answers = {};
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String id, Object? value) {
    setState(() {
      if (value == null) {
        _answers.remove(id);
      } else {
        _answers[id] = value;
      }
    });
    widget.onChanged(Map.of(_answers));
  }

  Widget _label(BuildContext context, FeedbackQuestion q) {
    final t = context.ndText;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: q.label),
        if (!q.required)
          TextSpan(
              text: '  ${tr('nd-qs-feedback-optional')}',
              style: t.small.copyWith(color: context.nd.textMuted)),
      ]),
      style: t.label.copyWith(fontSize: 15, height: 22 / 15),
    );
  }

  Widget _input(BuildContext context, FeedbackQuestion q) {
    final value = _answers[q.id];
    final on = widget.enabled;
    switch (q.kind) {
      case FeedbackKind.rating:
        return FeedbackStars(
            value: value is int ? value : 0,
            label: q.label,
            onChanged: on ? (v) => _set(q.id, v) : null);
      case FeedbackKind.text:
        final c = _text.putIfAbsent(q.id, () => TextEditingController());
        return NdField(
          controller: c,
          semanticLabel: q.label,
          lines: q.long ? 3 : 1,
          maxLength: 2000,
          enabled: on,
          onChanged: (v) => _set(q.id, v.trim().isEmpty ? null : v),
        );
      case FeedbackKind.yesno:
        return Align(
          alignment: Alignment.centerLeft,
          child: _Choices<bool>(
            label: q.label,
            options: [(true, translate('Yes')), (false, translate('No'))],
            value: value is bool ? value : null,
            row: true,
            onChanged: on ? (v) => _set(q.id, v) : null,
          ),
        );
      case FeedbackKind.choice:
        return _Choices<String>(
          label: q.label,
          options: [for (final o in q.options) (o, o)],
          value: value is String ? value : null,
          onChanged: on ? (v) => _set(q.id, v) : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          _label(context, widget.questions[i]),
          const SizedBox(height: 8),
          _input(context, widget.questions[i]),
        ],
      ],
    );
  }
}

/// One to five stars; a click on a star sets that many.
class FeedbackStars extends StatelessWidget {
  const FeedbackStars(
      {super.key, required this.value, required this.label, this.onChanged});

  /// 0 for none yet.
  final int value;
  final String label;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return Semantics(
      label: label,
      value: value == 0 ? null : tr('nd-qs-stars', [value]),
      container: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          NdIconButton(
            icon: i <= value ? NdIcons.starFilled : NdIcons.star,
            tooltip: tr('nd-qs-stars', [i]),
            size: 40,
            iconSize: 30,
            color: i <= value ? c.accent : c.textMuted,
            onPressed: onChanged == null ? null : () => onChanged!(i),
          ),
      ]),
    );
  }
}

/// Options as radio rows, or side by side with [row] (yes and no).
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.row = false,
  });

  final String label;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final bool row;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final items = [
      for (final (v, text) in options)
        NdPressable(
          label: text,
          selected: value == v,
          inMutuallyExclusiveGroup: true,
          onPressed: onChanged == null ? null : () => onChanged!(v),
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4, right: row ? 24 : 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              NdRadioMark(selected: value == v, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(text,
                    style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
              ),
            ]),
          ),
        ),
    ];
    return Semantics(
      label: label,
      container: true,
      child: row
          ? Row(mainAxisSize: MainAxisSize.min, children: items)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: items),
    );
  }
}
