# Pre-P3 Legislation Relations and Metadata Refinement

Date: 2026-06-30

## Scope

This checkpoint strengthens legislation metadata before P3 export work.

Implemented behavior:

- Schema v6 adds `legislation_relations`, a normalized relation table between
  legislation documents.
- Schema v7 adds `legislation_details.legislation_type_other`.
- Legislation details now preserve legislation number, legislation year,
  effective date, repeal date, and expanded effective statuses.
- Choosing legislation type `other` in document review shows a required custom
  type text field.
- Metadata normalization and draft save preserve the new legislation fields.
- Valid metadata edits to a document already in `copied_to_library` keep that
  workflow state. Invalidating edits still return the document to review.
- Legislation relation UI is available inside document review and shows related
  document titles/codes.

## Verification

- Manual user testing accepted the custom type field, save/display behavior,
  and copied-to-library edit behavior.
- Fresh local verification before commit:
  - `flutter analyze`: no issues.
  - `flutter test`: 1482 tests passed.
  - `git diff --check`: no whitespace errors; only Windows line-ending
    warnings.

## P3 Impact

P3 export should include the new legislation detail fields in `type_details`.
P3.1 should decide whether legislation relations are exported as embedded
incoming/outgoing arrays per document or as a separate relation file keyed by
`document_code`.
