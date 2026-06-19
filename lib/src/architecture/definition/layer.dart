/// The architectural layers recognized by the analyzer.
///
/// In Clean Architecture, dependencies flow inward toward [domain]: [presentation]
/// may depend on [application] and [domain]; [application] depends on [domain];
/// [data] depends on [domain]; never the reverse. [core] is shared infrastructure
/// any layer may use. [unknown] covers files that don't sit in a recognized layer
/// directory (e.g. `lib/main.dart`, `lib/app.dart`).
enum Layer {
  data,
  domain,
  application,
  presentation,
  core,
  unknown;

  /// Whether this is one of the four feature layers (not [core]/[unknown]).
  bool get isFeatureLayer =>
      this == Layer.data ||
      this == Layer.domain ||
      this == Layer.application ||
      this == Layer.presentation;
}

/// The sub-folder a file lives in inside a feature layer.
///
/// These mirror the target tree (`data/{datasources,models,repositories}`,
/// `domain/{entities,repositories,usecases}`,
/// `application/{services,coordinators,facades}`,
/// `presentation/{providers,pages,widgets}`). [none] is used for files that are
/// directly under a layer (or under `core/`) without a recognized sub-folder.
enum Sublayer {
  datasources,
  models,
  repositories,
  entities,
  usecases,
  services,
  coordinators,
  facades,
  providers,
  pages,
  widgets,
  none,
}
