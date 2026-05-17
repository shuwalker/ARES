# Release notes

Historical Hermes Desktop release notes live in this folder to keep the repo
root focused on the app, packaging, and trust-facing docs.

## Tag policy

- Official release tags use the `vX.Y.Z` format, for example `v0.8.1`.
- The published GitHub Release should point to the exact tagged commit used to
  build `HermesDesktop.app.zip`.
- For local release candidates before tagging, it is fine to package with an
  explicit `HERMES_VERSION=0.8.1`, but that artifact should not be presented as
  the final public release unless the tag and commit match.
- Once the final tag exists, prefer packaging from that tagged commit without
  version overrides so the app bundle, manifest, checksum, and release page all
  describe the same build.
