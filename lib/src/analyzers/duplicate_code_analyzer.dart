import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../analysis/analyzer.dart';
import '../analysis/path_utils.dart';
import '../models/finding.dart';
import '../models/project_paths.dart';
import '../services/ignore_service.dart';

/// Detects highly similar (likely copy-pasted) Dart files under `lib/` using
/// token-based similarity.
///
/// This is a lightweight v1 focused on finding duplicated *files* — it is not
/// widget-tree analysis. Each file is reduced to a normalized token stream
/// (comments removed, whitespace collapsed, string and numeric literals
/// replaced with the `STRING`/`NUMBER` placeholders), and pairs of files are
/// compared with Jaccard similarity over overlapping token shingles. Pairs at
/// or above [similarityThreshold] are reported.
///
/// ## Limitations (regex-based, no AST)
/// Normalization is deliberately regex-based, so a few edge cases are handled
/// imperfectly:
/// - Strings containing comment-like text (`'http://x'`) or comments containing
///   quotes may confuse comment/string stripping.
/// - Raw strings (`r'...'`), triple-quoted strings, and string interpolation
///   (`'$x'`) are not understood specially.
/// - Only *local* ordering is captured (via shingles); large-scale reordering
///   of blocks can lower the score.
/// - Comparison is O(n²) over the eligible files, which is fine for typical
///   project sizes but not tuned for very large monorepos.
class DuplicateCodeAnalyzer implements Analyzer {
  const DuplicateCodeAnalyzer();

  static const String rule = 'duplicate_code';

  /// Minimum Jaccard similarity (0.0–1.0) for a pair to be reported. Not yet
  /// CLI-configurable by design.
  static const double similarityThreshold = 0.80;

  /// Files with fewer normalized tokens than this are excluded from comparison.
  /// This removes noise from barrel files, stubs, and (near-)empty files, which
  /// would otherwise score near-identical to each other.
  static const int _minTokens = 30;

  /// Number of consecutive tokens per shingle (k-token window).
  static const int _shingleSize = 3;

  @override
  String get name => 'duplicate-code';

  @override
  Future<AnalysisResult> analyze(ProjectPaths paths) async {
    final libDir = Directory(paths.libDir);
    if (!libDir.existsSync()) return AnalysisResult.empty(name);

    final ignore = IgnoreService.forProject(paths.root);

    // 1. Collect every Dart file under lib/ as a forward-slash key. Staying
    //    inside libDir excludes test/, .dart_tool/, and .build/ by construction.
    //    Ignored files are dropped here, so they never become comparison
    //    candidates and never produce findings.
    final keys = <String>[
      for (final entity in libDir.listSync(recursive: true))
        if (entity is File && p.extension(entity.path) == '.dart')
          if (!ignore.isIgnored(toPosixRelative(paths.root, entity.path)))
            toPosixRelative(paths.root, entity.path),
    ]..sort();

    // 2. Build a shingle set per eligible file (those above the token floor).
    final shingles = <String, Set<String>>{};
    for (final key in keys) {
      final file = File(p.join(paths.root, p.joinAll(key.split('/'))));
      final tokens = _tokenize(file.readAsStringSync());
      if (tokens.length < _minTokens) continue;
      shingles[key] = _shingleSet(tokens);
    }

    // 3. Compare every unordered pair; emit one finding per similar pair.
    final eligible = shingles.keys.toList()..sort();
    final findings = <Finding>[];
    for (var i = 0; i < eligible.length; i++) {
      for (var j = i + 1; j < eligible.length; j++) {
        final a = shingles[eligible[i]]!;
        final b = shingles[eligible[j]]!;
        final score = _jaccard(a, b);
        if (score >= similarityThreshold) {
          final percent = (score * 100).round();
          findings.add(Finding(
            rule: rule,
            path: eligible[i],
            severity: Severity.info,
            message:
                'Highly similar to ${eligible[j]} ($percent% similarity).',
          ));
        }
      }
    }

    return AnalysisResult(analyzerName: name, findings: findings);
  }

  /// Reduces Dart [source] to a normalized list of tokens.
  List<String> _tokenize(String source) {
    var s = source;
    // Strip block comments, then line comments.
    s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
    s = s.replaceAll(RegExp(r'//[^\n]*'), ' ');
    // Replace string literals (with escape handling) with a placeholder.
    s = s.replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), ' STRING ');
    s = s.replaceAll(RegExp(r"'(?:\\.|[^'\\])*'"), ' STRING ');
    // Replace numeric literals (hex, decimal, exponent) with a placeholder.
    s = s.replaceAll(
      RegExp(r'\b0[xX][0-9a-fA-F]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b'),
      ' NUMBER ',
    );
    // Extract tokens: identifiers/placeholders and single punctuation chars.
    final tokenPattern = RegExp(r'[A-Za-z_$][\w$]*|[^\s\w]');
    return [for (final m in tokenPattern.allMatches(s)) m.group(0)!];
  }

  /// Builds the set of [_shingleSize]-token shingles for [tokens]. When there
  /// are fewer tokens than the shingle size, falls back to the token set.
  Set<String> _shingleSet(List<String> tokens) {
    if (tokens.length < _shingleSize) return tokens.toSet();
    final set = <String>{};
    for (var i = 0; i + _shingleSize <= tokens.length; i++) {
      set.add(tokens.sublist(i, i + _shingleSize).join(' '));
    }
    return set;
  }

  /// Jaccard similarity between two sets: |A∩B| / |A∪B|.
  double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final intersection = a.intersection(b).length;
    final union = a.length + b.length - intersection;
    return union == 0 ? 0.0 : intersection / union;
  }
}
