# Supare interaction design

Supare uses a calm emerald identity, warm light surfaces, matching dark surfaces, a custom check emblem, native system typography, and spacious Material 3 controls. The design borrows established interaction patterns rather than branded layouts: a chronological task list, direct completion controls, a persistent add action, editable task sheets, and a wallet organized by people. These patterns reduce navigation and make the result of an action visible.

Four permanent destinations match the user’s mental model: Today includes overdue work, Upcoming shows future plans, Wallet protects documents, and Settings controls appearance, permissions and backups. Completion history is a filter rather than a fifth section. Search remains local. Task actions expose explicit rescheduling and deletion. Permission failures preserve task data and explain why a reminder is not scheduled.

The wallet opens locked. Family chips and document search reduce the time needed to find a field while filling a form in another app. Identifiers start masked; individual copy actions avoid exposing an entire document. Preview and OS sharing remain explicit, with an explanation that recipient apps control files once shared. Import forms make optional data optional; family membership and document name remain clear required inputs.

Touch controls use standard minimum hit areas, text can wrap, forms scroll above keyboards, and navigation scales to phone widths. Lists have informative empty states and async actions report errors. Manual cropping uses four adjustable corners and can be cancelled without saving. No charts, activity dashboards, sample documents, promotional screens or remote fonts are included.

Widget tests exercise navigation, task form validation, PIN gating and crop output. Device accessibility, large-text, landscape, VoiceOver/TalkBack and low-memory behavior remain acceptance checks in DEVICE_TESTS.md; the existence of adaptive widgets does not establish those checks passed.
