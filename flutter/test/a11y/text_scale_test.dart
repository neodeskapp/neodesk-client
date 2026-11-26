// WCAG 1.4.4 Resize Text: the app follows the system text size up to
// 200 %, and the shared controls grow with the text instead of clipping it.
// (findings.md F39, F40)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/fixtures.dart';
import '../nd/harness.dart';

/// Pumps [child] under the app's text scale builder with the system text
/// size at [system], and returns the scale the child sees.
Future<double> _seen(WidgetTester tester, double system,
    {Widget? child}) async {
  late double seen;
  await pumpScreen(
      tester,
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(system)),
        child: Builder(
            builder: (outer) => ndTextScaleBuilder(
                outer,
                Builder(builder: (inner) {
                  seen = MediaQuery.of(inner).textScaler.scale(10) / 10;
                  return child ?? const SizedBox();
                }))),
      ),
      size: const Size(480, 720));
  return seen;
}

List<String> _overflows(List<FlutterErrorDetails> errors) => errors
    .where((d) => d.exceptionAsString().contains('overflowed'))
    .map((d) => d.exceptionAsString().split('\n').first)
    .toList();

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('the system text size is followed from 100 to 200 %',
      (tester) async {
    expect(await _seen(tester, 1.5), 1.5);
    expect(await _seen(tester, 2.0), 2.0);
    expect(await _seen(tester, 3.0), 2.0, reason: 'clamped at 200 %');
    expect(await _seen(tester, 0.8), 1.0, reason: 'never smaller');
  });

  testWidgets('buttons and fields grow with 200 % text', (tester) async {
    await _seen(tester, 2.0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          NdButton(label: 'Connect', onPressed: () {}),
          const SizedBox(height: 8),
          const SizedBox(width: 300, child: NdField(placeholder: 'Remote ID')),
        ]));
    // The label needs this much height at its width; a fixed-height box
    // would squeeze it smaller and cut it off.
    final label = tester.renderObject<RenderParagraph>(find.text('Connect'));
    final needs = label.getMinIntrinsicHeight(label.size.width);
    expect(label.size.height, greaterThanOrEqualTo(needs - 0.5),
        reason: 'the label is clipped: ${label.size.height} < $needs');
    expect(tester.getSize(find.byType(NdButton)).height,
        greaterThanOrEqualTo(needs));
    final field = tester.getSize(find.byType(EditableText));
    final box = tester.getSize(find.byType(NdField));
    expect(box.height, greaterThanOrEqualTo(field.height));
  });

  testWidgets('quick support consent holds 200 % text', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = old);
    await _seen(tester, 2.0,
        child: NdWindowFrame(
          titleBar: NdTitleBar(
            height: 36,
            brand: NdTitleBrand(title: tr('nd-qs-window-title')),
            controls: NdWindowControls(
                onMinimize: () {}, onClose: () {}, height: 36),
          ),
          child: QuickSupportView(
            state: const OnboardingState(
              phase: OnboardingPhase.supportConsent,
              server: fernServer,
              company: fernCompany,
              supporterName: 'Mara Jensen',
            ),
            onAllow: (_) {},
            onDecline: () {},
            onCancel: () {},
            onClose: () {},
            onRetry: () {},
          ),
        ));
    FlutterError.onError = old;
    expect(_overflows(errors), isEmpty);
  });
}
