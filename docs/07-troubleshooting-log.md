# Troubleshooting Log

Real problems hit while building the lab, and how they got fixed.

## Windows Packer smoke test: blocked by free trial

**Error:**
```
Windows VM instances are not included with the free trial.
```

**Cause:** GCP free trial projects block Windows VMs outright. Not a quota or config issue.

**Fix:** Upgraded to a billing-enabled account. Free trial credit carried over.

**Lesson:** Check account tier before debugging config when an error names a policy restriction directly.

## Windows Packer smoke test: stuck on "Waiting for WinRM"

Instance created fine, Windows activated, WinRM setup completed per the serial console. Packer still couldn't connect, and timed out after 20 min.

**Steps taken:**
- Checked serial console — guest OS was fine, WinRM was configured.
- Ran `gcloud compute start-iap-tunnel` manually against port 5986 to isolate network vs. WinRM. Failed with a generic connection error.
- Checked VM service account, firewall rule, IAP API enabled — all correct.
- Re-ran the manual tunnel impersonating `packer-deployer` — got "resource not found," because Packer's own timeout had already deleted the instance by then.
- Realized the real question: Packer's `impersonate_service_account` covers instance creation, but the IAP tunnel step can still use my own local gcloud identity instead.
- Checked IAM: `packer-deployer` had `roles/iap.tunnelResourceAccessor`. My own account didn't.

**Fix:** Granted my account `roles/iap.tunnelResourceAccessor`, unconditional.

**Lesson:** `impersonate_service_account` doesn't necessarily cover every step — the IAP tunnel can fall back to your own credentials. When something IAP-fronted hangs and everything else checks out, check the human identity too, not just the service account.

Isolating each layer (guest OS, firewall, IAP API, service account, human account) one at a time is what actually found it — faster than re-reading the same Packer output over and over.

## Windows Packer: image build failed on deprecation permission

First real (non-smoke-test) build got all the way through image creation, then crashed:
```
Error setting image deprecation status: googleapi: Error 403: Required
'compute.images.deprecate' permission ... forbidden
```
Packer itself then crashed with an unrelated Go panic while handling that error — a Packer plugin bug, not something wrong with the config.

**Cause:** `packer-deployer` could create images but not deprecate the previous image in the family, which Packer attempts automatically on every build.

**Fix:** Created a custom IAM role `packerImageManager` (create/get/list/delete/deprecate/useReadOnly on images), bound to `packer-deployer`. Managed via Terraform (`terraform/iam.tf`), imported after being created manually to unblock the build first.

**Side issue while fixing this:** `terraform import` of the custom role failed with `iam.roles.get` permission denied — `terraform-deployer` had never been granted IAM role management. Fixed by granting `roles/iam.roleAdmin`.

**Near-miss:** after editing `iam.tf` to add a `stage = "GA"` field, a `terraform plan` showed the IAM member binding would be destroyed — turned out an edit had accidentally dropped that resource block from the file. Caught by reading the full plan output before applying, not just skimming it.

**Lesson:** Always read the full `terraform plan` output, especially the `to destroy` count, before typing yes — a small unrelated edit can silently drop a resource from config and queue a real deletion.

## Windows Packer: image had to be rebuilt after a mid-build crash

Laptop lost power mid-build. Packer's own cleanup (delete instance/disk on error) never ran, since the process was killed outright.

**Recovery steps:**
- Checked for orphaned resources: `gcloud compute instances list`, `gcloud compute disks list`, `gcloud compute images list`.
- Found a leftover running instance (deleted it), and a leftover disk that survived the instance deletion (deleted separately).
- Found the image from the deprecation-permission crash had actually completed successfully despite that crash — deleted it anyway to start clean once the plan was to rebuild with agents included.

**Lesson:** An interrupted Packer run doesn't clean up after itself. Always check instances → disks → images (in that order) after any abnormal exit before assuming the project is in a known state.

## Windows Packer: stuck downloading Elastic Agent

Elastic Agent provisioner hung 15+ min on `Invoke-WebRequest` downloading the agent zip. No error, just never finished.

**Cause:** `Invoke-WebRequest`'s default progress-bar rendering badly slows down large downloads over a remote WinRM session — a known PowerShell issue, not specific to this setup.

**Fix:** Added `-UseBasicParsing` to the `Invoke-WebRequest` call. Rebuild completed in under 30 min total, agent installed cleanly.

**Lesson:** Any `Invoke-WebRequest` downloading something non-trivial in a Packer/WinRM provisioner should use `-UseBasicParsing` by default, not just when it breaks.

## Golden image v1 shipped

First real Windows golden image built successfully: `purple-windows-workstation-20260822023748`. Includes Elastic Agent binary (unenrolled, pinned to 9.5.2). CALDERA agent intentionally not baked in — it's generated live by the CALDERA server at runtime, not a static downloadable binary.

## CALDERA Packer build: apt-get update failed on port 80

First CALDERA build failed at the very first `apt-get update` -- every mirror timed out on port 80, even though `allow-packer-https-egress` (443) was already in place and had worked for every prior build.

**Cause:** Ubuntu's default apt sources use plain HTTP, not HTTPS. Nothing built before this needed `apt-get`, so the gap was never exposed -- the Windows and Ubuntu workstation builds only ever used HTTPS (`curl` for Elastic Agent, and Windows apt-equivalents happen over HTTPS by default).

**First attempt at a fix:** rewrote apt sources to force HTTPS (`sed -i 's|http://|https://|g' ubuntu.sources`). Partially worked -- `security.ubuntu.com` supports HTTPS fine, but Google's own regional mirror (`us-central1.gce.archive.ubuntu.com`) does not, and every request to it timed out on 443 instead.

**Actual fix:** added a dedicated `allow-packer-http-egress` firewall rule (port 80), rather than continuing to force HTTPS. Confirmed with a real failed connection attempt, not a guess -- GCE's regional mirror genuinely has no HTTPS listener.

**Lesson:** A working HTTPS rule doesn't mean a dependency actually needs HTTPS. Confirm with the real error, not the fix that seems more secure on paper -- forcing HTTPS here would have kept failing indefinitely against a mirror that doesn't support it.

## CALDERA Packer build: UI build failed on Node.js version

CALDERA install (git clone, pip install) succeeded, but the UI build step crashed:
```
Vite requires Node.js version 20.19+ or 22.12+.
```
Ubuntu 24.04's `apt` package for `nodejs` is 18.19.1 -- same class of problem as the Go version issue: Ubuntu's package archive lags well behind what current tooling expects.

**Fix:** added NodeSource's official repo (`deb.nodesource.com`) and installed Node 22.x from there instead of `apt`'s default package.

**Lesson:** Same pattern as Go -- don't trust Ubuntu's `apt` version for fast-moving toolchains (Node, Go). Check the actual version constraint the software states, and pin from an upstream source when `apt`'s version is behind.

## CALDERA golden image shipped

First real CALDERA control image built successfully: `purple-caldera-control-20260822203246`. Full install verified working end to end during the build -- CALDERA actually started (`All systems ready.`), UI assets built, systemd service installed and enabled, Elastic Agent binary installed (unenrolled). All three golden images (Windows workstation, Ubuntu workstation, CALDERA control) now exist and are proven.
