import 'dart:io';

/// ANSI escape codes used for colored terminal output.
class _Ansi {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String cyan = '\x1B[36m';
  static const String gray = '\x1B[90m';
}

/// Handles all formatted terminal output for the CLI.
///
/// Colors are emitted using ANSI escape codes and are automatically
/// disabled when the output is not an interactive terminal (for example,
/// when piped to a file), keeping captured output clean.
class Logger {
  Logger({bool? useColor, IOSink? out, IOSink? err})
      : useColor = useColor ?? stdout.supportsAnsiEscapes,
        _out = out ?? stdout,
        _err = err ?? stderr;

  /// Whether ANSI color codes should be emitted.
  final bool useColor;

  final IOSink _out;
  final IOSink _err;

  String _paint(String text, String color) =>
      useColor ? '$color$text${_Ansi.reset}' : text;

  /// Prints a success line, prefixed with a green check mark.
  void success(String message) =>
      _out.writeln('${_paint('✓', _Ansi.green)} $message');

  /// Prints an error line (to stderr), prefixed with a red cross.
  void error(String message) =>
      _err.writeln('${_paint('✗', _Ansi.red)} $message');

  /// Prints a warning line, prefixed with a yellow exclamation mark.
  void warn(String message) =>
      _out.writeln('${_paint('!', _Ansi.yellow)} $message');

  /// Prints an informational line, prefixed with a cyan dot.
  void info(String message) =>
      _out.writeln('${_paint('•', _Ansi.cyan)} $message');

  /// Prints a line without any prefix or styling.
  void plain(String message) => _out.writeln(message);

  /// Prints a bold heading followed by an underline divider.
  void heading(String title) {
    _out.writeln(_paint(title, '${_Ansi.bold}${_Ansi.cyan}'));
    _out.writeln(_paint('─' * title.length, _Ansi.gray));
  }

  /// Prints a blank line.
  void blank() => _out.writeln();
}
