import 'dart:io';

import 'package:flutter_cleanup/flutter_cleanup.dart';

Future<void> main(List<String> args) async {
  exitCode = await CliRunner().run(args);
}
