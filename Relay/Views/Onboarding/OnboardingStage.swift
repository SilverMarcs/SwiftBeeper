#if REMOTE_ONLY
enum OnboardingStage {
    case automatic
    case remoteConnection
    case remoteSetup
    case beeperSignIn
}
#endif
