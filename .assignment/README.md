# Assignment issue definitions

`manifest.json` and the files under `issues/` are the source of truth for the assignment issues. They are versioned with the application so a duplicated repository can import the issues that match its checked-out revision.

## Updating definitions

1. Keep each issue `id` stable after release. The importer uses it to detect an existing issue.
2. Use `order` to control creation order. Values must be unique. The importer waits one second between newly created issues so GitHub's creation-date sort order remains stable.
3. Put issue prose in the Markdown file referenced by `body`.
4. Refer to another assignment issue as `{{issue:stable-id}}`. The importer replaces it with the destination repository's issue number after all issues have been created.
5. Update `assignment_version` when releasing a changed set of assignment issues.
6. Run `scripts/test-import-assignment-issues.sh` before committing changes.

The importer preserves finalized issues by default so an applicant's edits are not lost. Pass `--update-existing` only when the repository owner intentionally wants to restore all managed fields from these definitions.
