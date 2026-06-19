import 'layer.dart';

/// Where a single Dart file sits in the architecture, derived purely from its
/// project-relative path.
///
/// This is a plain value object produced by the layer classifier and consumed by
/// every rule. It carries no behavior beyond a few convenience predicates so that
/// rules read declaratively (`info.isDomainContract`) instead of re-deriving path
/// facts.
class LayerInfo {
  const LayerInfo({
    required this.layer,
    required this.sublayer,
    this.feature,
    this.isCore = false,
    this.isRouterDir = false,
  });

  /// A file that doesn't belong to any recognized layer.
  static const unknown = LayerInfo(layer: Layer.unknown, sublayer: Sublayer.none);

  /// The architectural layer this file belongs to.
  final Layer layer;

  /// The recognized sub-folder within the layer, or [Sublayer.none].
  final Sublayer sublayer;

  /// The owning feature (`lib/features/<feature>/…`), or null for core/unknown.
  final String? feature;

  /// Whether the file lives under `lib/core/`.
  final bool isCore;

  /// Whether the file lives under `lib/routing/` (the blessed routing home).
  final bool isRouterDir;

  /// `domain/repositories` — the repository *contracts* other features may share.
  bool get isDomainContract =>
      layer == Layer.domain && sublayer == Sublayer.repositories;

  /// `domain/entities`.
  bool get isEntity => layer == Layer.domain && sublayer == Sublayer.entities;

  /// `domain/usecases`.
  bool get isUseCase => layer == Layer.domain && sublayer == Sublayer.usecases;

  /// `data/models`.
  bool get isModel => layer == Layer.data && sublayer == Sublayer.models;

  /// `data/datasources`.
  bool get isDatasource =>
      layer == Layer.data && sublayer == Sublayer.datasources;

  /// `data/repositories` — the repository *implementations*.
  bool get isRepositoryImpl =>
      layer == Layer.data && sublayer == Sublayer.repositories;

  /// `presentation/pages`.
  bool get isPage =>
      layer == Layer.presentation && sublayer == Sublayer.pages;

  /// `presentation/providers`.
  bool get isProvider =>
      layer == Layer.presentation && sublayer == Sublayer.providers;
}
