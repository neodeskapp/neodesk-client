// The app's onboarding service, on the generated bridge to the client core.

import '../models/platform_model.dart';
import 'onboarding_service.dart';
import 'onboarding_service_ffi.dart';

class BindOnboardingNative implements OnboardingNative {
  const BindOnboardingNative();

  @override
  String state() => bind.mainOnboardState();

  @override
  bool isQuickSupport() => bind.mainOnboardIsQuickSupport();

  @override
  void redeemJoin(String text) => bind.mainOnboardRedeemJoin(text: text);

  @override
  void redeemSupport(String text) => bind.mainOnboardRedeemSupport(text: text);

  @override
  void consent(bool allow) => bind.mainOnboardConsent(allow: allow);

  @override
  void endSupport() => bind.mainOnboardEndSupport();

  @override
  void sendChat(String text) => bind.mainOnboardSendChat(text: text);
}

/// The one onboarding service of the app. The link handler in common.dart
/// passes betterdesk://join and betterdesk://support links to it.
final FfiOnboardingService onboardingService =
    FfiOnboardingService(const BindOnboardingNative());

/// Makes [onboardingService] the one the screens use; main.dart calls it
/// at start.
void registerOnboardingService() {
  OnboardingService.registered = onboardingService;
}
