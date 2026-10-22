# Addon development plan

Goal: reduce corrections through verified requirements, small changes, automated checks and beta testing. No process guarantees bug-free code.

## Before implementation

1. Inspect the current source, installed version and GitHub branch. Reconcile local and remote history without discarding work. The initial import used connector commits separately from local commits; check divergence before the next change.
2. State the player-visible outcome, supported client and acceptance criteria. Record unknown API behavior explicitly. Ask only questions that change the implementation.
3. Present the implementation and validation plan for user review before feature coding. Include files affected, saved-data changes, rollback and any required in-game checks.

## Implementation and validation

4. Work on a feature branch. Keep changes scoped and preserve working behavior and saved settings.
5. Maintain runnable Lua tests and syntax checks. The recovered Professions tests and new diagnostic recorder tests now run through Lupa's Lua 5.1 runtime on Windows. Add meaningful checks for changed calculations, missing APIs, restricted values, bank snapshots and saved-data migrations where applicable.
6. Run automated checks, review the diff and verify TOC references, load order and packaged files. Report exactly which checks ran and which remain pending.
7. Test updater installation and backup/restore against temporary game-folder fixtures, including download failure and missing destination. Validate changes in a beta client before promoting to the stable update source.
8. Use a short in-game checklist: load without Lua errors, exercise the feature, reload, check settings persistence, and confirm existing addon behavior still works. Have the user perform checks requiring gameplay access.

## Release

9. Keep experimental changes off the updater's main branch. Promote after applicable automated checks and beta acceptance. Record version, changes, limitations and rollback instructions; tag known good releases.
10. Verify published downloads match the intended release. Never label an untested in-game behavior as verified.

## Immediate next work to plan

- Keep local and GitHub history synchronized; the earlier separate import histories were reconciled before diagnostic work.
- Monitor the added Windows GitHub Actions workflow; local Lua 5.1 recorder and Professions checks pass, but hosted CI results must be checked separately.
- Add updater fixture tests for installation, backup and error handling.
- Plan a stable release source so the updater installs tested releases rather than arbitrary main changes.
- Verify the actual Forever launch folder and client APIs at launch. Transfer addon settings separately only after backups and an explicit migration plan.

This document records the proposed workflow. It does not claim that these checks or release controls already exist.
