# Copilot Control Center

Flutter UI prototyped in `copilot_control_center_ui` and mirrored in this app.

## Run

```bash
flutter pub get
flutter run -d chrome
```

Run on Android with `flutter run -d android` when an emulator or device is
connected. Building an APK is supported with `flutter build apk --release`.
iOS builds require macOS and Xcode.

## Default application and explicit demo

- `/` opens the authenticated, backend-connected `/workspace`. It validates the
  server session before displaying user data; signed-out users see login.
- Only `/demo` opens the local prototype described below. No demo data is
  injected into the live workspace. SDK task execution is still unavailable;
  switching the entry point does not enable an executor.

## Prototype limitations (`/demo` only)

- The UI uses local sample data and does not connect to the application backend,
  Copilot SDK, or GitHub APIs.
- Changes are kept only in memory and reset when the app restarts.
- GitHub settings links open the official GitHub website.
- Do not enter real tokens or secrets into the demonstration forms.

## Backend integration in progress

- Only `/demo` opens the prototype. Do not wrap its sample
  workspace in authentication and treat its local actions as persisted data.
- `AuthenticatedWorkspaceGate` is the tested authentication boundary for the
  backend-connected workspace. It validates `/api/session` with the
  server before mounting private UI; a stored token alone is not proof of login.
- An expired session opens login and clears local credentials. A network/server
  failure shows an error with retry, without clearing valid credentials.
- Each authenticated workspace gets an independent Riverpod container. Logging
  out destroys user-specific provider state so another login cannot inherit it.
  Logout failures propagate to the caller and do not report successful logout.
- `/connect` mounts the gate and the real account-connections screen using the
  current app theme, without mounting any sample workspace. Users can register
  or log in, authorize GitHub in the same browser tab, refresh connections, and
  log out. `/auth/complete` exchanges the verified OAuth handoff and returns to
  `/connect`; the callback URI is captured before Flutter navigation starts.
  GoRouter owns these paths and preserves the callback query until exchange;
  web URLs use the path strategy, not manual history updates.
  These routes are a setup surface, not the completed workspace integration.
- `/workspace` is an authenticated, seed-free beta using the prototype's shared
  theme and shell. It connects persisted role creation/editing/merging, explicit
  templates, projects and shared briefs/context, generic file upload/download/
  deletion, and the main-account repository selector with pagination.
- Team creation uses a shared project, selected definitions and an explicit
  GitHub account per new instance. The task step provides bot chips, editable
  assignments and priorities. Saving creates the team/instances/tasks atomically,
  without starting agents. Team detail connects membership changes, task CRUD
  and statuses, and the versioned collaboration graph. It is not a separate
  sidebar destination.
- Project details include all project tasks, including legacy tasks without a
  team. Remote files stay metadata rather than being represented by empty local
  byte arrays. Partial uploads retain only unsent drafts; quotas include remote
  files. Deletion verifies the backend's HTTP 204 contract.
- Wizard file drafts survive switching steps and must be uploaded or removed
  before saving the team. Refresh failures explicitly retain cached data and
  open forms; errors do not fabricate a successful save.
- Team tasks have an explicit OpenAI confirmation dialog, persistent analysis
  history and asynchronous polling. It sends the saved project brief/context,
  current PDF versions, supported attachments, roles and existing tasks. Valid
  output adds missing assigned/prioritized tasks atomically, never starts bots
  and never replaces existing tasks. A changed source rejects application of
  the result but still accounts for known provider usage.
- The backend must explicitly enable OpenAI. Limits are USD 1 per logical
  analysis and USD 10 globally per UTC request-start month. Unknown charges
  retain their reservation; neither the server nor the UI retries paid calls
  automatically. Lost POST responses reuse the same request UUID. Closing the
  dialog stops polling, not the persistent server job. Costs shown are token
  price estimates, not invented billing balances.
  Tests: `flutter test test/workspace_analysis_test.dart`.
- **Koszty i kredyty** loads owned OpenAI accounting and real per-account
  GitHub quota metadata. Unknown provider data is not rendered as zero or
  invented USD. Quota refresh is an asynchronous read-only job without a
  conversation or inference. Polling stops when the page is disposed.
- SDK extra-spend policy is persisted in exact USD cents with optimistic
  version checking. Conflicts and failed refreshes retain unsaved edits.
  The policy does not change GitHub billing settings; runtime enforcement is
  still pending with the disabled executor. Native SDK Auto and each bot's
  selected GitHub subscription are separate from OpenAI analysis billing.
  Tests: `flutter test test/workspace_costs_test.dart`.
- SDK execution, AI repository scanning, and persistence for prototype-only
  features remain pending.
- Authentication regression tests: `flutter test test/authenticated_workspace_test.dart`.
- Setup and callback regressions: `flutter test test/backend_setup_test.dart`.
- `workspace_data.dart` validates the new shared-project/role-definition API
  without sample-data or empty-list fallbacks. File upload/download methods
  preserve binary bytes and use the existing authenticated Dio transport.
  These adapters are mounted in the private beta, not in the prototype. Tests:
  `flutter test test/workspace_data_test.dart test/workspace_file_api_test.dart`.
- Beta UI regressions:
  `flutter test test/live_workspace_roles_test.dart test/live_workspace_projects_test.dart test/live_workspace_teams_test.dart`.
- The beta calendar reuses the prototype's weekly editor, but loads schedules
  for actual team-instance IDs and persists explicit IANA timezones and ISO
  weekdays 1-7. The week overview displays saved values, not failed edits.
  Successful API saves validate the returned owner and complete schedule.
  Scheduling SDK start/stop is still unavailable and is explicitly labelled.
  Regression tests: `flutter test test/workspace_schedule_test.dart`.

## Calendar and review feedback

- **Kalendarz** configures one weekly schedule per bot: weekdays, start/end time
  in the browser's local time, and an enabled switch. Save changes to update
  the week overview. End time must be later than start time on the same day;
  overnight windows are not supported.
- Schedules are illustrative only: they do not start or stop bots.
- **Do poprawek** requires written instructions before rejecting a stage.
  Instructions are shown with the stage on the dashboard and team detail.
  Cancelling leaves the stage awaiting approval.
- Schedules and feedback survive navigation but reset on page refresh.

## Team briefs, files, and task assignments

- Attach PDF documents, images, and other files to revision feedback, bot
  messages, or the team's **PDF** step. Files are held as bytes locally, not
  uploaded. Limits: 10 MB per file and 30 MB per attachment collection.
- Messages may contain files without text; revision feedback still requires
  written instructions. Attachments may be removed before submission.
- **Projekt** selects a main demonstration GitHub account and a sample
  repository. **GitHub** selects a demonstration account for each selected bot.
  Neither list is fetched from GitHub or represents verified OAuth connections.
- **PDF** holds the full brief and supporting files, without an analysis button.
  **Zadanie** contains editable tasks with bot assignments. Removing a bot
  requires reassigning its tasks before saving.
- **Analizuj dokument przez AI** is located only in **Zadanie** and explains
  that AI is not configured. It does not send files or fabricate generated tasks.
- Editing a team restores its saved brief, attachments, accounts, and tasks;
  all of this remains in memory and resets on refresh.

## Team workspace and custom bots

- **Boty i role → Dodaj własnego bota** creates a local bot with a unique name,
  role, description, sample account, and sample plan. Custom bots are available
  in team creation, assignments, collaboration graphs, costs, and the calendar.
- **Projekty i PDF** opens read-only task details, materials, progress, and the
  team's task list. Editing materials is an explicit action, not the default
  project click.
- Tasks and **Współpraca** belong to each team's overview, not the side menu.
  Tasks can be added, edited, assigned, deleted, and have their status updated.
  The collaboration graph supports editing each bot's supervisor and prevents
  cycles. Removing a bot from the team also removes its hierarchy relations.
- Team creation is available only in **Zespoły AI**, not every page header.
  **Ustawienia** remains the last navigation item.
- **Wyloguj** calls the existing logout API and clears stored credentials only
  after server confirmation (an already expired session is also accepted).
  Network or server errors are shown without reporting success. The signed-out
  screen can reopen a fresh public demonstration; the demo is not an
  authenticated workspace and refreshing it still opens the public demo.

## Bot task planning and repository context

- The team's **Zadanie** wizard step groups tasks by bot using selector buttons
  with counts. Each task has an assignee, status, and priority (Niski, Normalny,
  Wysoki, Pilny). Priorities survive team edits and are visible in team/project
  task lists. Tasks whose bot was removed appear under **Taski bez bota** and
  must be reassigned or removed before the team can be saved.
- **Profil projektu**, within a team's overview, contains its repository and
  a manually editable context brief. **Skanuj repozytorium z AI** only explains
  the missing GitHub/AI configuration: no scan or automatic analysis is run.
- **Przekaż kontekst botom** lets the user choose team members and copies the
  repository, manual context, task brief, each bot's assigned tasks (including
  status and priority), and supporting files to their local
  demo chats. It does not contact the bots or SDK. Cancelling changes nothing.
  Empty context cannot be shared. All context and chat data resets on refresh.
