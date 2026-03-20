# EPsychInfo

`EPsychInfo` centralizes repository and release metadata for EPsych. It is used by the startup banner, saved protocol metadata, and the RunExpt version dialog.

## Usage

```matlab
info = EPsychInfo();
disp(info.Version)
disp(info.latestTag)
meta = info.meta;
```

## Metadata Fields

- `Version`: EPsych release version string.
- `DataVersion`: Data format version string.
- `chksum`: Latest commit checksum parsed from the local git checkout.
- `commitTimestamp`: Timestamp of the latest entry in `.git/logs/HEAD`.
- `latestTag`: Latest reachable git tag reported by `git describe --tags --abbrev=0`.
- `meta`: Struct snapshot combining the core metadata fields with a current timestamp.

## Notes

- `latestTag` returns an empty character vector when Git is unavailable or the repository has no reachable tags.
- `commitTimestamp` and `chksum` rely on the local `.git` directory being available.