# Prometheus CIPP overlay

Production image: `ghcr.io/prometheus-it/cipp-container:latest`. The image keeps this name after the repository rename to `CIPP-Prometheus`, so Azure continues following the same update source.

| File | Purpose |
| --- | --- |
| `Invoke-CIPPStandardPrometheusTeamsExternalChatFiles.ps1` | Custom Teams standard implementation. |
| `standards.json` | Portal label, help text and required Enabled/Disabled choice; added to both the frontend and backend standards catalogs. |
| `pipeline.py` | Resolve a stable CIPP release, apply the overlay and verify the built image. |
| `tests/` | Compatibility and policy behavior tests. |
| `build-state.json` | Last successful build and scheduled workflow activity; maintained by CI. |

## Updates

[The publisher](../.github/workflows/prometheus-container.yml) checks the latest official
stable release daily at 04:17 UTC. It builds that release's exact commit with this overlay,
runs both test suites and checks the packaged backend, portal and version metadata before
publishing a versioned image and updating `latest`. Failed checks leave `latest` unchanged.
CIPP's existing container updater follows the configured image repository.

Application versions use SemVer build metadata, for example `11.0.2+prometheus.<commit>.<hash>`.
CIPP considers that the same stable release as `11.0.2` while still warning about newer
official releases. Docker tags use `-prometheus` instead because image tags cannot contain
`+`; `build-state.json` records both. The updater compares complete version strings so it
also detects new custom builds of the same official release.

Overlay or workflow changes trigger a new build. `build-state.json` avoids unchanged
rebuilds and periodically records activity to keep GitHub's schedule enabled. Keep the
inherited container publishers disabled; preserve their files and the other CI workflows.
Use Actions and `build-state.json` for build provenance. Do not reset this overlay with
GitHub's **Sync fork** button.

## Standard and recovery

The standard controls only `FileSharingInChatsWithExternalUsers` on the assigned tenant's
Global Teams Files policy. Report reads only; Remediate applies the explicit Enabled or
Disabled choice and verifies the result. SharePoint and OneDrive restrictions still apply.
Assign tenant exceptions through the appropriate customer delta template.

The pipeline currently supports this one custom standard. Adding another requires extending
`pipeline.py` and its tests as well as adding the implementation and catalog entry.

To roll back application code, pin Azure to a previously published version image. Saved
templates remain in Azure storage. Image rollback does not undo Microsoft 365 policy changes;
select Disabled and remediate separately to reverse this sharing setting.
