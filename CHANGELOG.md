# Changelog

## [Unreleased]

### Fixed

- On Windows, `--unpin-program=zipnote` (and `zipcloak`, `zipsplit`) now selects
  that program. The previous binary rejected the option outright; only the
  installed command names worked.
