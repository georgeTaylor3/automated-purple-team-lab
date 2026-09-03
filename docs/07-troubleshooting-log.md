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

## control-node: boot disk filled completely, cascading failures

IAP tunnel and SSH connections to control-node started failing
intermittently, then consistently, with a generic "Unexpected error while
connecting" from gcloud. Retries that had worked before stopped working.

**Diagnosis process:**
- `gcloud compute ssh ... --troubleshoot` flagged low disk space as a
  possible cause, based on Google's own connectivity diagnostic.
- Confirmed directly via the serial console: Elasticsearch's own logs
  showed `java.io.IOException: No space left on device` repeatedly,
  plus Docker's log driver failing to even write container logs for the
  same reason. Not a guess -- the disk was genuinely, completely full.

**Root cause:** the boot disk was 30GB, sized before Fleet Server was
added. Elasticsearch + Kibana + Fleet Server + CALDERA together, plus
Docker's own image/build cache accumulated across every rebuild, filled
it entirely.

**Fix:**
- Resized the disk live, 30GB -> 50GB, via `terraform apply`. This
  needed a new IAM permission on `terraformComputeInstanceManager`
  (`compute.disks.resize`) -- Terraform had never resized a disk
  before, only create/delete/use.
- GCP resized the disk live, in place -- confirmed via `terraform plan`
  showing "updated in-place", not a destroy+recreate. This meant
  Elasticsearch and Fleet Server's data survived, unlike every previous
  `control-node` change this project has made.
- Growing the disk doesn't grow the filesystem automatically --
  `gcloud compute instances reset` was needed to trigger cloud-init's
  filesystem growth on boot. Confirmed via `df -h /` before and after.

**Collateral damage:** CALDERA's `conf/default.yml` was mid-write when
the disk hit zero free space, leaving a 0-byte file behind. CALDERA
doesn't regenerate this file if missing or empty -- it crashed on
startup with `IndexError: list index out of range` trying to parse it.

**First fix attempt was wrong:** deleted just the empty file, expecting
CALDERA or Docker to regenerate it. This produced a different error
(`FileNotFoundError`) and made it worse. The actual cause: Docker only
auto-populates a named volume from the image's baked-in files once, the
first time that volume is attached to a container. Since `caldera-conf`
already existed from an earlier deploy, deleting one file inside it
didn't trigger Docker to re-copy anything from the image.

**Actual fix:** removed the whole volume (`docker volume rm
purple-lab_caldera-conf`), then recreated the container. This triggered
Docker's real first-time auto-populate behavior, restoring a genuinely
intact `default.yml` from the image.

**Lesson:** a full disk doesn't just block new writes -- it silently
corrupts whatever was mid-write at the moment it filled, in every
service running on that disk, not just the one that reported the
error first. When recovering from disk exhaustion, check every
service's data for torn writes, not just the one that's loudest about
it. And named Docker volumes only auto-populate from the image once,
at creation -- deleting a file from an existing volume never
regenerates it from the image; only removing the whole volume does.


## Terraform apply reports success but the same diff keeps reappearing

`terraform apply` on `allow-target-to-fleet-server-ingress` reported
"Modifications complete" twice, removing `source_ranges` -- but the
next `terraform plan` showed the identical diff again both times.

**Confirmed directly against the live resource** (not trusting
Terraform's own report):
```
gcloud compute firewall-rules describe allow-target-to-fleet-server \
  --format="yaml(sourceRanges,sourceServiceAccounts)"
```
`sourceRanges` was genuinely still present on GCP's side, despite two
successful-looking applies.

**Cause (likely):** GCP's firewall API appears to treat an omitted
field on an `UPDATE` call as "leave unchanged" rather than "clear it."
Terraform's in-place update path never actually sent an explicit
empty value for the field.

**Fix:** force a full destroy+recreate instead of an in-place update:
```
terraform apply -replace="google_compute_firewall.allow_target_to_fleet_server_ingress"
```
A `CREATE` call sends the complete desired state, which correctly
omitted the field this time. Confirmed via the same `gcloud describe`
check afterward.

**Lesson:** "Apply complete" is not the same as "the live resource
actually matches what I intended." When the identical diff reappears
after a reportedly successful apply, verify against the live resource
directly before assuming Terraform's own state is correct.

## Elastic Agent enrollment failed: control-node was stopped

First real workstation target (`linux-workstation-target`) failed to
enroll with Fleet at boot, with `connection timed out` reaching
`10.60.10.39:8220`.

**Cause:** `control-node` (and therefore Fleet Server) is deliberately
stopped between sessions to save cost. The workstation target booted
and ran its enrollment script before anyone had started `control-node`
back up -- nothing was listening at all.

**Fix (immediate):** started `control-node`, waited for its own
deploy sequence to finish, then manually re-ran the enrollment command
directly on the workstation target rather than waiting for a full
reboot.

**Fix (durable):** added a reachability wait loop to
`boot-agent-enrollment.sh` -- polls Fleet Server's host:port via raw
TCP up to 20 times (5 minutes) before attempting enrollment, instead
of failing on the first attempt with no retry.

**Lesson:** this project's whole premise is stopping instances between
sessions to save cost -- any boot-time script that depends on another
instance being up needs to tolerate that instance still being mid-boot
or not yet started, not assume it's already there.

## First workstation target had no admin SSH access at all

After deploying `linux-workstation-target`, `gcloud compute ssh` to it
failed. Checked every existing firewall rule
(`gcloud compute firewall-rules list --format="table(name,targetServiceAccounts)"`)
and found none targeted `workstation-target-sa` for inbound traffic at
all -- every existing IAP-SSH rule targeted `packer-builder-sa` or
`control-node-sa` specifically.

**Fix:** added `allow-iap-to-workstation-target-ssh`, same pattern as
the existing `control-node` admin-access rule.

**Lesson:** each new workload identity needs its own explicit admin
access rule -- it doesn't inherit reachability from any other
identity's rules, no matter how similar the pattern looks.
