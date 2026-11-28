# Publish a Nauvim release

The [Desktop release workflow](../.github/workflows/release.yml) runs when a
pull request from a `release/vX.Y.Z` branch in this repository merges into
`main`. Use the same version in `pubspec.yaml` and `rust/Cargo.toml`.

The workflow checks the package versions and tags the merged commit as
`vX.Y.Z`. It then builds and tests that commit on Ubuntu 24.04 (x86-64 and
aarch64) and macOS (Apple Silicon). After the checks pass, it publishes a
GitHub Release with the three archives, `SHA256SUMS`, and generated notes.
The macOS app uses an ad hoc signature. The workflow can package it without
an Apple Developer Program membership.

## Publish a version

1. Run the [release build](building.md#release-build) and
   [desktop integration check](development.md#desktop-integration) on the
   platforms available to you.
2. From the `release/vX.Y.Z` branch, push and open a pull request into `main`.

   ```sh
   git push -u origin HEAD
   ```

3. Merge the pull request. When the release run succeeds, check the new version on
   [GitHub Releases](https://github.com/nauvim/nauvim/releases).

For a transient failure, rerun the workflow from **Actions**. A retry reuses
the tag when it points to the same merged commit.
