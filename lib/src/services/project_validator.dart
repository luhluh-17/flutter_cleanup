import 'dart:io';

import '../models/project_paths.dart';
import '../models/validation_result.dart';

/// Validates that a directory looks like a Flutter/Dart project that the
/// tool can operate on.
///
/// This service performs only file-system checks and returns a
/// [ValidationReport]; it does no printing, which keeps it easy to unit test
/// and reusable by any command.
class ProjectValidator {
  const ProjectValidator();

  /// Checks the structure of the project at [paths] and returns a report.
  ///
  /// Rules:
  /// - `pubspec.yaml` is required (error if missing).
  /// - `lib/` is required (error if missing).
  /// - `assets/` is optional (informational when missing).
  ValidationReport validate(ProjectPaths paths) {
    final results = <ValidationResult>[];

    if (File(paths.pubspec).existsSync()) {
      results.add(ValidationResult.ok('pubspec.yaml found',
          detail: paths.pubspec));
    } else {
      results.add(ValidationResult.error('pubspec.yaml not found',
          detail: paths.pubspec));
    }

    if (Directory(paths.libDir).existsSync()) {
      results
          .add(ValidationResult.ok('lib/ directory found', detail: paths.libDir));
    } else {
      results.add(ValidationResult.error('lib/ directory not found',
          detail: paths.libDir));
    }

    if (Directory(paths.assetsDir).existsSync()) {
      results.add(ValidationResult.ok('assets/ directory found',
          detail: paths.assetsDir));
    } else {
      results.add(ValidationResult.warning('assets/ directory not present',
          detail: 'Optional — skipping asset checks.'));
    }

    return ValidationReport(results);
  }
}
