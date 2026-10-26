# Historical parser experiments

The archive preserves 109 original files from commit `db21f3b41e77dda2a3fe56b99e60ca33054f5b64`:
parser prototypes, runners, input fixtures, measurements, reviews, and the earlier
native-adoption and release-readiness reports. Their bytes are unchanged;
`parser-experiments-2026-10-25.json` records each SHA-256 and the archive digest.

This is historical evidence, not maintained implementation. Prototype APIs,
workspace paths and portable-fallback descriptions may be obsolete. Current
behavior belongs to [the migration guide](../../MIGRATION.md),
[browser support](../../BROWSER-SUPPORT.md) and the design. Current measurements
are indexed in [BENCHMARKS.md](../../BENCHMARKS.md).

Extract `parser-experiments-2026-10-25.tar.gz` into a disposable directory to
inspect the original layout. Reproduction also needs the source revisions and
toolchains named in each capture; extracting the archive alone is insufficient.
Do not run historical mutation scripts against the current checkout or overwrite
captured results. The same files remain in Git history at the source commit.
