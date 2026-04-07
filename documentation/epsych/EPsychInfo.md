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
- `commitTimestamp`: Timestamp of the latest entry in `.git/logs/HEAD`.
- `latestTag`: Latest reachable git tag reported by `git describe --tags --abbrev=0`.
- `meta`: Struct snapshot combining core metadata fields with a current timestamp.

## Notes

- `latestTag` returns an empty character vector when Git is unavailable or the repository has no reachable tags.
- `commitTimestamp` and `chksum` rely on the local `.git` directory being available.