/// Stamped at build time via `--dart-define=BUILD_TIME=...` so Settings can
/// show exactly which build is installed - handy when pushing frequent
/// updates during development.
const buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: 'dev');
