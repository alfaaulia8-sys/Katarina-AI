# KATARINA Error Supervisor — GitHub Prior-Art References

Status: REVIEWED / IMPLEMENTED LOCALLY

Selected references:

- Badgerati/Pode file-watcher implementation patterns:
  https://github.com/Badgerati/Pode/blob/89797a301afec7611c55cd395f841fe78812ae01/src/Listener/Protocols/File/BufferingFileSystemWatcher.cs
- pytest-dev/pytest machine-readable test result patterns:
  https://github.com/pytest-dev/pytest/blob/f5240bef4d8b31232d570fb80ea4f7c50b087d1b/src/_pytest/junitxml.py
- actions/upload-artifact CI artifact retention patterns:
  https://github.com/actions/upload-artifact/blob/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/README.md
- terrylica/mql5-crossover MT5 automation/log location prior art:
  https://github.com/terrylica/mql5-crossover/blob/0c4bf7b36e922e8a19947463af1659b63042f4a5/docs/guides/MT5_FILE_LOCATIONS.md

KATARINA adaptation:

- Errors are pushed only to branch `katarina-errors`, never directly to `main`.
- Each bundle records the source commit and diagnostic context.
- Sensitive credential-like values are redacted before publication.
- If GitHub is unavailable, bundles remain queued locally and are retried.
- The supervisor is diagnostic infrastructure and cannot enable live risk or execution.
