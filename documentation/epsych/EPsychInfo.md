# EPsychInfo

`EPsychInfo` centralizes repository and release metadata for EPsych. It is used by the startup banner, saved protocol metadata, and the RunExpt version dialog.

## Usage

```matlab
info = EPsychInfo();
disp(info.Version)
disp(info.latestTag)
meta = info.meta;
```

## Properties

### Constant properties

- `Version`: EPsych release version string.
- `DataVersion`: Data format version string.
- `Author`: Author name.
- `AuthorEmail`: Author contact email.
- `License`: License name string.
- `LicenseURL`: URL pointing to the license text.
- `Copyright`: Copyright notice string.
- `RepositoryURL`: GitHub repository URL.
- `CommitHistoryURL`: URL to the commit history overview document.
- `WikiURL`: GitHub wiki URL.
- `DocumentationURL`: URL to the main README or documentation landing page.

### Read-only properties (SetAccess = private)

These properties can be read from outside the class but cannot be set externally.

- `iconPath`: Absolute path to the EPsych icon asset directory (a subdirectory of the installation root).
- `chksum`: Latest commit checksum parsed from the local git checkout.
- `stimgenChksum`: Latest commit checksum of the `obj/stimgen` submodule.
- `commitTimestamp`: Timestamp of the latest entry in the checkout's `logs/HEAD` reflog.
- `latestTag`: Latest reachable git tag reported by `git describe --tags --abbrev=0`.
- `worktree`: Name of the git worktree backing this checkout, as git records it under `.git/worktrees`. Empty for a repository's main working tree.
- `meta`: Struct snapshot combining core metadata fields with a current timestamp.

## Notes

- `latestTag` returns an empty character vector when Git is unavailable or the repository has no reachable tags.
- `commitTimestamp` and `chksum` rely on the checkout's git directory being available; both are unavailable in a zip download.
- Git directories are resolved rather than assumed. A linked worktree — like a submodule — keeps a one-line `.git` *file* holding `gitdir: <path>` instead of a folder, so its HEAD and reflog live elsewhere; reading `.git/logs/HEAD` directly finds nothing there.
- `meta.Worktree` records the worktree in saved session metadata, since two checkouts of the same commit can still differ in uncommitted work. The RunExpt title bar and its Version Info dialog show the same name whenever the session is running from a worktree.