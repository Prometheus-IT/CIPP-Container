# Prometheus CIPP stable container

This fork uses released CyberDrain/CIPP source and a small overlay in this directory.
Production image: `ghcr.io/prometheus-it/cipp-container:latest`.

The daily GitHub Actions workflow selects the latest official stable release, resolves
its exact commit, applies the custom standard without changing existing catalog entries,
runs policy and compatibility tests, and builds the official release Dockerfile.
It checks the compiled backend export, portal bundle and version metadata before publishing
an immutable version image and moving `latest`. A failed check leaves the last published
`latest` image intact. GitHub reports failed runs to the workflow subscribers.

Custom version suffixes change when the overlay or workflow changes, so CIPP's existing
container updater detects both official releases and custom fixes. The updater follows
the configured GHCR repository and restarts the Azure app at its existing update time.
No Azure credential, CIPP SAM token, customer secret or tenant data is stored in this repository.

`build-state.json` records the last successful upstream commit and custom version. A periodic
activity commit prevents GitHub disabling the daily schedule after 60 days of inactivity.
Only the Prometheus publisher should be enabled for this fork's production image. Keep
the inherited workflow files for reference and CI, but disable the inherited container
publishers in Actions so they cannot publish an image without the overlay.

## Custom standard

`PrometheusTeamsExternalChatFiles` appears under Teams Standards. It controls only
`FileSharingInChatsWithExternalUsers` on the assigned tenant's Global Teams Files policy.
Choose Enabled or Disabled explicitly. Report mode reads only. Remediation writes only
that property when different, then reads it again before recording success.
SharePoint and OneDrive restrictions still apply; client propagation can take several hours.

Assign Enabled with Report and Remediate only to the customer delta template `SET-Delta-OST`.
Do not add this exception to the shared baseline. Remove Remediate or select Disabled to
stop/reverse enforcement as required.

## Initial deployment and recovery

1. Enable the publisher workflow and run it. Make the GHCR package public: it contains
   application code only. Azure and CIPP's current updater use anonymous image pulls.
2. Verify the build succeeds and the exact version image can be pulled anonymously.
3. Record Azure's current container configuration, then change only its image to
   `ghcr.io/prometheus-it/cipp-container:latest`. Retain SSO, storage, Key Vault,
   managed identity, app plan and updater settings.
4. Verify CIPP sign-in, existing templates, backend and frontend version, and the new
   standard. Run the standard in Report mode for Openstorage before remediation.
5. Confirm the intended tenant policy readback after applying remediation.

Rollback Azure to the previous recorded version image, or to the original
`ghcr.io/cyberdrain/cipp:latest` if that is still the intended official version.
Pin a previous custom version image to stop automatic channel updates during investigation.
The Azure storage account retains saved templates across image changes; rolling back an
image does not undo a Microsoft 365 policy write. To undo sharing, apply Disabled separately.

If an upstream contract changes, the automated build stops for review. Fix this overlay and
rerun the workflow; do not bypass tests or reset this fork with GitHub's Sync fork button.
The build uses exact released source, so this fork's source snapshot may appear behind main
while its container is current. Use Actions summaries and build-state.json for deployed provenance.
