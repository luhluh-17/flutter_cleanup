/// The format in which a command renders its results.
///
/// Only [text] is implemented today. [json] is declared up front so commands
/// and printers can be written to be format-aware now, letting a future
/// `--json` flag be wired in without reworking the output layer.
enum OutputFormat {
  text,
  json,
}
