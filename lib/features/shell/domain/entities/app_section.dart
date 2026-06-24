/// The primary navigation sections of the desktop shell.
///
/// This is a presentation-agnostic domain concept: labels, icons and tooltips
/// are resolved in the presentation layer from localization, not stored here.
enum AppSection {
  dashboard,
  import,
  documents,
  review,
  categories,
  duplicates,
  settings,
  administration,
}
