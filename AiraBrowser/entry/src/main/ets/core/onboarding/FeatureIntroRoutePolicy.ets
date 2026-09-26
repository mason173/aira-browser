export type InitialOnboardingDestination = 'feature_intro' | 'startup_welcome' | 'browser';
export type FeatureIntroExitDestination = 'startup_welcome' | 'browser';

/**
 * The feature intro is only for a brand-new install that has not finished the
 * sync welcome. An existing install that already passed that welcome goes
 * straight to the browser, even if this intro version was added later.
 */
export function resolveInitialOnboardingDestination(
  featureIntroCompleted: boolean,
  startupWelcomeCompleted: boolean
): InitialOnboardingDestination {
  if (startupWelcomeCompleted) {
    return 'browser';
  }
  if (!featureIntroCompleted) {
    return 'feature_intro';
  }
  return 'startup_welcome';
}

export function resolveFeatureIntroExitDestination(
  startupWelcomeCompleted: boolean
): FeatureIntroExitDestination {
  return startupWelcomeCompleted ? 'browser' : 'startup_welcome';
}
