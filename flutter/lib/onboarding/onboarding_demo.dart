import 'dart:async';

import 'onboarding_service.dart';

/// A walk through the onboarding screens with made-up data, for looking at
/// them in a debug or profile build:
///   NEODESK_DEMO_ONBOARDING=first-start   join flow (code 7KQ4-M2XD joins,
///                                            ABCD-EFGH fails as used)
///   NEODESK_DEMO_ONBOARDING=quick-support consent, waiting, the session
///                                            bar after 3 s, chat
/// Release builds ignore the variable (see main.dart).
class DemoOnboardingService extends FakeOnboardingService {
  DemoOnboardingService.firstStart()
      : super(const OnboardingState(phase: OnboardingPhase.notSetUp)) {
    stepDelay = const Duration(milliseconds: 900);
  }

  DemoOnboardingService.quickSupport()
      : super(
          const OnboardingState(
            phase: OnboardingPhase.supportConsent,
            server: 'help.fernhill.example',
            company: 'Fernhill IT',
            supporterName: 'Mara Jensen',
            companyPhone: '+49 30 5550 1420',
            accentHex: '#3aa35c',
            fileName: 'NeoDesk-QuickSupport-help.fernhill.example-R8TW3NPA',
          ),
          true,
        );

  Timer? _timer;

  @override
  Future<void> redeemJoin(String linkOrCode) {
    final input = InviteInput.parse(linkOrCode);
    nextJoinError = input.code == 'ABCDEFGH' ? OnboardingError.usedUp : null;
    emit(current.copyWith(
      company: 'Fernhill IT',
      deviceName: 'Reception PC',
      folder: 'Front desk',
      accentHex: '#3aa35c',
    ));
    return super.redeemJoin(linkOrCode);
  }

  @override
  Future<void> consent(bool allow) async {
    await super.consent(allow);
    if (!allow) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      emit(current.copyWith(phase: OnboardingPhase.supportInSession));
      _timer = Timer(const Duration(seconds: 4), () {
        emit(current.copyWith(inputActive: true, messages: [
          OnboardingChatMessage(
              fromSupporter: true,
              text: "I'm opening the printer settings now.",
              time: DateTime.now()),
        ]));
      });
    });
  }

  @override
  Future<void> endSupport() async {
    _timer?.cancel();
    await super.endSupport();
  }
}
