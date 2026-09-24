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

## IAP tunnel instability: coffee shop wifi, VPN, and a workaround worth keeping

Kibana and CALDERA's browser UI became unreliable partway through tonight's
session -- tunnels would report `Listening` but then either hang
indefinitely (spinner never resolving) or throw repeated
`ConnectionCreationError: Unexpected error while connecting` on individual
sub-streams.

**Diagnosis process, ruling out causes one at a time:**

1. Confirmed `control-node` itself was healthy throughout (`gcloud compute
   instances describe ... --format="value(status)"` returned `RUNNING`
   consistently, docker containers all `Up`).
2. Confirmed basic connectivity was fine (`ping -c 5 8.8.8.8` showed 0%
   packet loss).
3. Initially suspected the coffee shop wifi itself, or Proton VPN adding
   an unstable extra hop -- installing NumPy into gcloud's *bundled*
   Python interpreter (a separate, isolated Python from the system one --
   see below) resolved the throughput *warnings* but not the harder
   connection *errors*.
4. Moved to stable home fiber wifi (~1Gb, actively streaming Netflix and
   Spotify with zero issue) -- tunnel instability continued. This ruled
   out network quality as the cause entirely.
5. Root cause never fully identified. Genuinely inconclusive -- worth
   revisiting if it recurs, rather than assuming any single fix (NumPy,
   network change) is the complete answer.

**gcloud's bundled Python detail, worth remembering:** `gcloud info | grep
-i python` shows gcloud ships its own fully separate Python interpreter
(`/usr/lib/google-cloud-sdk/platform/bundledpythonunix/bin/python3`),
isolated from the system's `python3` and from `~/.local` site-packages.
Installing a package via regular `pip` has zero effect on gcloud's own
Python unless installed directly into that bundled interpreter, or
`CLOUDSDK_PYTHON_SITEPACKAGES=1` is set to let it see the system
site-packages.

**The actual workaround that unblocked the session:** rather than fight
the browser tunnel further, authenticated to CALDERA's API directly via
its session-cookie login endpoint, from an SSH session on `control-node`
itself (SSH remained reliably stable throughout, even when browser
tunnels didn't):

```
curl -c /tmp/caldera_cookies.txt -X POST http://localhost:8888/enter \
  -d "username=red&password=admin"
```

From there, every subsequent CALDERA API call used `-b
/tmp/caldera_cookies.txt` for auth, and Elasticsearch was queried directly
via `-u elastic:PASSWORD` -- both entirely as `localhost` traffic on the
VM itself, no tunnel round-trip through the client machine's network at
all. This let the actual operation get launched, monitored, and closed
out even while the browser remained unreliable.

See `docs/14-caldera-elastic-api-reference.md` for the specific commands
captured from tonight, worth reusing directly next time a tunnel is
flaky rather than re-deriving them.

## CALDERA's Discovery adversary profile loops on boilerplate system accounts

The built-in "Discovery" adversary profile's `atomic_ordering` lists 12
distinct techniques, but a real operation against a freshly-provisioned
Ubuntu target ran the same technique ("Process Discovery" / T1057,
`ps aux | grep #{host.user.name}`) 25 times in a row before the session
was manually closed.

**Cause, confirmed via the operation's own `chain` data:** an earlier step
("Account Discovery: Local Account") enumerated `/etc/passwd` and found
CALDERA/facts for every system service account on the box (`list`,
`daemon`, `sync`, etc. -- standard Ubuntu boilerplate, not real users).
CALDERA's atomic planner then correctly, one at a time, tried "Process
Discovery" against each of those usernames -- since none of them have any
actual running processes, each attempt produces no useful result
(`status: -3`), and the planner moves to the next discovered username
rather than the next *technique* in the ordering.

**This is expected planner behavior, not a bug.** The atomic planner
selects the next available ability whose requirements are satisfied by
current facts -- it has no built-in judgment about whether a fact (a
boring system account name) is actually worth pursuing. A target with
more real user accounts, or a smaller seeded fact set, would move through
the technique list more directly.

**Worth remembering for future demo design:** an automated Discovery
operation against a bare, just-provisioned target can spend a long time
grinding through low-value system accounts before reaching anything more
distinctive. For a public demo with a strict time budget (see the
planned 15-minute session timer), this is worth accounting for --
either by seeding fewer/no boilerplate account facts, choosing a
different starter profile, or accepting that "watch it work through
housekeeping first" is itself a realistic, honest thing to show a
visitor about how automated recon actually behaves.


## CALDERA Sandcat agents got a new identity on every restart

Every stop/start of a target instance was creating a brand-new CALDERA
agent record, accumulating dead/untrusted entries in the UI indefinitely.

**First theory, tested and disproven:** assumed Sandcat's identity was
baked into the compiled binary at download time, so reusing the
already-downloaded file across boots (instead of re-downloading) would
preserve identity. Implemented, tested via a real stop/start cycle --
the binary was correctly reused (confirmed in the boot log), but CALDERA
still assigned a brand-new paw anyway. Disproven by direct evidence, not
assumption.

**Actual cause:** Sandcat generates a fresh identity on every process
*start*, regardless of whether the binary file itself is new or old.
Identity is a property of the running process's registration handshake
with the server, not something fixed at compile time.

**Real fix:** Sandcat has a documented `-paw` flag ("Optionally specify a
PAW on initialization"). Both boot scripts now pass
`-paw "$(hostname)"` explicitly on every start -- a fixed, deterministic
identity derived from the instance's own hostname, rather than letting
CALDERA assign a random one. Verified on both `linux-workstation-target`
and `web-target`: multiple stop/start cycles now report back as the
exact same agent every time, confirmed via the Fleet-equivalent CALDERA
agents API (`GET /api/v2/agents`), not just the UI.

**Lesson:** when a system generates identity/state you don't control,
check whether it exposes an explicit override before working around it
indirectly. The binary-reuse approach was a reasonable first guess, but
testing it honestly (rather than assuming reuse = identity persistence)
is what caught it being wrong.

## Elastic Agent's real install path differs from where it's downloaded

`sudo /opt/elastic/elastic-agent/elastic-agent status` returned a
connection error (`.sock: no such file or directory`), suggesting the
agent wasn't running -- despite Elastic Defend and Fleet enrollment both
working correctly moments earlier.

**Cause:** `elastic-agent install` copies itself to its own canonical
system location (`/opt/Elastic/Agent/`, capitalized, a completely
different path) rather than running from wherever the tarball was
originally extracted and installed from
(`/opt/elastic/elastic-agent/`, lowercase -- the path used in this
project's boot scripts and golden images). The lowercase path holds the
original installer copy, which is never actually run again after
installation; the real, live daemon lives at the uppercase path.

**Fix:** check status against the real installed location:
```
sudo /opt/Elastic/Agent/elastic-agent status
```

**Lesson:** confirmed via `ps aux` first, not assumed -- the actual
running processes' paths (`/opt/Elastic/Agent/data/...`) were the real
evidence pointing at the correct check command, rather than continuing
to trust a status command that was silently checking the wrong binary.

## Fleet policy assignment silently determines which integrations run

`web-target`'s Elastic Agent had been enrolled into the *workstation*
Fleet policy since its original deployment, not the *web-server* policy
-- despite both being created and the web-server policy having Nginx
added to it earlier in the project. The agent was simply never assigned
to the right one, so nginx log data never flowed, with no error
anywhere pointing at the actual cause.

**Fix:** reassigned the agent to the correct policy directly in Fleet's
UI (Agents -> agent -> Assign to new policy). Took effect live, no
reboot or reinstall needed.

**Momentary confusion during the fix:** `elastic-agent status`
immediately after reassignment showed `DEGRADED` on the Defend
component, specifically `"Applied policy {...}"`. This resolved on its
own within a minute or two and did not indicate a real problem --
confirmed by checking the actual functional outcome (real nginx data
landing in Elasticsearch) rather than continuing to chase the status
label itself.

**Lesson:** a correctly-configured integration on a policy does nothing
if the actual agent was never assigned to that policy in the first
place. Worth checking which policy an agent is actually on as a first
step, not just whether the policy itself is configured correctly.

## CALDERA's --insecure flag bypasses login authentication entirely

While preparing to store CALDERA's `red` credential in Secret Manager
for the demo controller's `/attack` endpoint, found that
authentication was not actually being enforced at all -- any username
and any password, including a deliberately wrong one, returned the
same successful `302` from `/enter`.

**Confirmed:**
```
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8888/enter \
  -d "username=red&password=totallywrongpassword12345"
```
Returned `302`, identical to a genuine correct login.

**Root cause:** `docker/caldera/Dockerfile`'s runtime `CMD` has
`--insecure`:
```
CMD ["/opt/caldera/venv/bin/python3", "server.py", "--insecure"]
```
This flag was there since the first CALDERA container
-- meaning authentication has never
actually been enforced!!, for the whole life of this project...

**Why now** the demo controller's `/attack`
endpoint (Increment 2, in progress) reaches CALDERA through a new
Cloud Run VPC egress path -- a less-controlled access route than IAP. 
Need to close now.

**A second, related finding:** every credential in `conf/default.yml`
(the two API keys, and all three user account passwords -- red, blue,
and the admin sub-user under the red group) were
random(tm) argon2 hashes 
-- not hashes of the literal word "admin" as commonly seen in CALDERA's own documented
defaults. 
-- This likely happened because the container's first boot never had
a `local.yml` override present, so CALDERA's own config generator
created random values and then hashed. fixing the --insecure flag would
have likely caused a hard lockout, since none of the stored password hashes
correspond to any password anyone actually knows.

**Interim fix completed tonight, not yet  fully enforced:**
- Created `conf/local.yml` on the persistent `caldera-conf` named
  volume (copy of `default.yml`, per CALDERA's own documented
  override pattern), with genuinely new, known passwords set for
  red, blue, and the admin sub-user (via targeted `sed` replacement
  of each specific hash, confirmed correct by re-reading the file
  after each change)
- Stored red's new password in Secret Manager
  (`caldera-red-password`), granted to `demo-controller-sa` only --
  the one identity with an actual, current need to read it. Blue and
  admin's new passwords deliberately NOT stored in Secret Manager,
  since neither has any automated consumer yet; kept in a personal
  password manager instead, matching the project's standing rule that
  Secret Manager holds only credentials with a real, current service
  consumer, never stored speculatively
- The server itself has NOT yet been restarted(im sleepy), and --insecure has
  NOT yet been removed from the Dockerfile -- ...
  vulnerability described above is technically still live as of this
  entry. Low practical risk overnight (control-node is reachable only
  via IAP tunnel and the one tagged Cloud Run firewall path, not the
  open internet).

**Next Time**
1. Remove `--insecure` from the Dockerfile's runtime `CMD` line only
   (leave the earlier build-time UI-asset-generation step's own
   `--insecure --build` flag untouched -- unrelated, never serves
   live traffic)
2. Rebuild the CALDERA image, redeploy `control-node`
3. Confirm the local.yml credentials set tonight persist correctly
   through the rebuild (conf/ is a named volume, expected to survive)
4. login with the new red password, and separately confirm a
   wrong password is now genuinely rejected -- the actual proof the
   fix worked, not just that the server restarted cleanly

**Lesson:** a flag like `--insecure` can be "recommended" or "part of the temaplte"
but was meant to be replaced...
indefinitely if nothing ever specifically depends on the security
property it disables -- worth periodically auditing "what would
happen if a stranger tried this right now," not just "does it work
for me via my own trusted access path."

## Git commit signing failed: "agent refused operation" (GNOME Keyring vs FIDO2)

`git commit -S` started failing with `Couldn't sign message (signer):
agent refused operation?` -- despite the resident YubiKey signing key
(set up several sessions ago) working correctly for many prior
commits.

**Diagnosis, ruling out causes in order:**
1. `ssh-add -l` confirmed the key was genuinely loaded/registered.
2. Reproduced the identical failure completely outside git, via raw
   `ssh-keygen -Y sign`, confirming this wasn't a git-specific config
   issue.
3. `echo $SSH_AUTH_SOCK` showed `/run/user/1000/keyring/ssh` -- GNOME
   Keyring's own SSH agent implementation, not standard OpenSSH
   `ssh-agent`.

**Root cause:** GNOME Keyring's SSH agent has a well-documented 
limitation with FIDO2 security keys specifically when a
PIN is required (`-O verify-required`, which this key was created
with) -- it cannot properly relay the touch+PIN confirmation flow the
way real OpenSSH `ssh-agent` can, and fails immediately with this
exact error rather than prompting or timing out. Confirmed via
multiple independent sources describing the identical symptom.

**Why this worked previously and only broke now:** not fully
determined -- possibly a session/login change that switched which
agent `SSH_AUTH_SOCK` pointed at, or GNOME Keyring's handling of this
specific key type was always marginal and this is the first time it
genuinely failed rather than happening to succeed.

**Immediate fix, confirmed working:**
```
unset SSH_AUTH_SOCK
git commit -S
```
Unsetting the variable forces git/ssh-keygen to talk to the hardware
key directly rather than through GNOME Keyring's broken relay. Needs
to be done in the current shell before signing.

**A secondary issue while testing, unrelated to the root cause:**
a manual `ssh-keygen -Y sign ... /dev/stdin` test failed separately
with `ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or
directory` -- piping input via `echo | ...` leaves no free terminal
for the key's own passphrase prompt, so it falls back to a GUI askpass
tool that wasn't installed. Fixed with:
```
sudo apt install ssh-askpass-gnome
```
This would have blocked real `git commit -S` calls too, not just the
manual test, since git's own signing flow pipes data the same way.

**Not yet done -- worth doing properly next session:** the permanent
fix, per every source describing this issue, is disabling GNOME
Keyring's SSH agent component entirely and using real `ssh-agent`
instead, so `unset SSH_AUTH_SOCK` doesn't need to be remembered every
session. this is a reliable workaround, not the root cause
resolution.

CALDERA login does not validate credentials, even without --insecure

Removed --insecure (previous session's finding), rebuilt and redeployed CALDERA. A wrong password still returns 302 -- identical to before the fix.

Checked, in order:

docker inspect caldera --format='{{.Config.Cmd}}' confirms --insecure is gone from the running command.
Server log states "Using main config from conf/local.yml" -- confirms the file with the new, known passwords is loading, not a cached default.yml.
Only one caldera container is running, freshly recreated by this deploy.
Build is current (commit from Aug 27 2026), not stale.

All four check out. A wrong password still authenticates.

Not a misconfiguration -- matches a known upstream issue. Multiple GitHub discussions on mitre/caldera and apache/caldera report the same symptom across different setups and versions: login succeeds regardless of password. No confirmed fix found. Likely a defect in app/service/auth_svc.py, not something fixable from this project's config.

Security posture: network-level access control -- IAP tunnel for admin use, the tagged Cloud Run firewall rule for the demo controller -- is the actual enforced boundary, and always has been. CALDERA's login screen is secondary and currently unreliable; treat it as such, not as a control to depend on.

Not pursued further tonight:

Check CALDERA's GitHub issues for this exact commit/version
Read auth_svc.py directly rather than treat it as a black box
Consider an older stable release instead of tracking master

## Fixed-paw Sandcat identity goes permanently untrusted after a stop/start

An agent with a stable, hostname-based paw (see prior session's fix)
showed `trusted: false` in CALDERA after a normal instance stop/start,
despite the agent process running correctly and beaconing.

**Confirmed:**
- Agent created four days earlier (`created` timestamp unchanged
  across many stop/starts -- the identity-stability fix is working as
  designed).
- Process genuinely running (`ps aux` showed the real PID matching the
  agent record).
- Only one recorded link/action in the agent's history, from the
  original creation -- no activity since, despite a recent `last_seen`.
- An operation launched against it finished instantly with zero steps
  -- consistent with the planner skipping untrusted agents entirely.

**Cause:** CALDERA agents default to `trusted: true` at creation and
flip to `false` via a server-side Untrusted Timer once an agent goes
silent longer than a configured threshold (commonly ~100-300s based
on real-world reports). Every deliberate instance stop (done for cost,
every session) leaves the agent silent for hours -- far past this
threshold -- triggering the flip.

**The real issue: trust does not appear to reliably recover once
lost, even when beaconing resumes normally.** A CALDERA pull request
(mitre/caldera#443) that would have added trust-recovery logic was
closed without merging. This project's own evidence is consistent with
that: the agent kept beaconing (recent `last_seen`) but stayed
untrusted regardless.

**This reveals a real tradeoff in the fixed-paw design, not just a
one-off glitch:** reusing the same identity across stop/starts (to
avoid duplicate agent clutter) also means inheriting that identity's
stuck-untrusted status every session, since trust state persists with
the identity rather than resetting.

**Fix used tonight:** delete the stuck agent
(`DELETE /api/v2/agents/{paw}`), kill the local process, restart it
with the same `-paw` value. Re-registers as a genuinely new agent
object internally, defaulting fresh to `trusted: true`.

**Open question, not resolved:** whether to keep the fixed-paw
approach (accepting a manual trust-reset step most sessions) or revert
to letting Sandcat generate a fresh identity each boot (accepting
agent-list clutter, but avoiding this trust problem entirely). Worth a
deliberate decision next time this comes up, not defaulting to either
silently.

## Group-based scenario scoping replaces fixed-paw identity

Following the trust-timer finding from the prior session: reverted
fixed-`-paw` Sandcat identity, replaced with CALDERA's own `-group`
flag to control which scenarios run on which box.

**Change:** each target now registers into a distinct group at boot
(`workstation-red`, `webserver-red`) instead of both sharing `red`.
`APPROVED_SCENARIOS` in `main.py` now maps each scenario to both an
adversary ID and a required group; `/attack` launches against that
specific group, not a shared one.

**Verified:**
- Fresh boot after the change: both agents registered with correct
  groups, `trusted: True` (confirmed via `/api/v2/agents`).
- `/attack` with `juice-shop-sqli` launched an operation scoped to
  `workstation-red` specifically. Operation's `host_group` contained
  exactly one member -- the workstation's real paw, trusted -- and did
  not include `web-target`. Group scoping works as designed.

**New finding, not yet resolved:** the operation's `chain` length was
`0` despite a correctly-scoped, trusted, eligible agent being present.
Operation showed `state: finished` immediately, no steps executed.
Distinct from the earlier trust-timer issue -- trust is confirmed
fine here.

**Not yet checked:**
- Whether the adversary profile still correctly references the
  ability (`GET /api/v2/adversaries`)
- The agent's reported platform/executors/privilege
  (`GET /api/v2/agents`) against what the ability's executor requires

## Password extraction bug: docker compose log line prefix

Following up on the --fresh/password-extraction:
the extraction step ran successfully (no warning), but the
published value failed to authenticate.

**Cause:** `docker compose logs` prefixes every line with the service
name (`caldera  | `). The multi-line password reconstruction captured
this prefix as part of the value -- e.g. `iMYkL0c...caldera|3oIFl...`
instead of the real, contiguous password.

**Fix:** strip the prefix before parsing:
```
docker compose logs caldera 2>&1 | sed -E 's/^caldera +\| ?//' | awk '...'
```

**Verified:** tested manually on control-node first -- confirmed clean 
extraction, confirmed via a real login (302 with a genuine
API_SESSION cookie) -- before applying to the committed script. Then
verified via a full terraform -replace: extraction,
publish, cleanup, and ability provisioning all completed with no
errors, no manual intervention.

## Fleet Server policy and target policies wiped -- same root cause as CALDERA

After the CALDERA --fresh fix, brought the full lab up for a normal
session. Fleet Server failed to start:
```
security_exception: failed to authenticate service account
[elastic/fleet-server] with token name [token-...]
```

**Diagnosis:**
1. Generated a new service account token directly against
   Elasticsearch -- succeeded, confirming Elasticsearch's security
   state no longer recognized the old one (stored, unchanged, in
   Secret Manager).
2. Published the new token, restarted Fleet Server -- authentication
   succeeded, but it then hung indefinitely: `"Waiting on policy with
   Fleet Server integration: fleet-server-policy"`.
3. `GET /api/fleet/agent_policies` returned zero policies. The
   Fleet Server container is hardcoded (via Terraform,
   FLEET_SERVER_POLICY_ID) to look for a policy literally named
   fleet-server-policy -- which no longer existed as the policies get
   wiped after every restart.
4. Recreated it via `POST /api/fleet/agent_policies` with that exact
   id. Fleet Server came up healthy immediately after.
5. Re-tried workstation-target enrollment -- failed with 401. Checked
   agent_policies again: still only fleet-server-policy exists.
   linux-workstation-policy and linux-webserver-policy, along with
   their Elastic Defend and System integrations, are also gone.

**Root cause: same as the CALDERA data aka not a
new problem.** Docker's named volumes (including Elasticsearch's own
data) live on control-node's boot disk. Every terraform -replace
during the CALDERA investigation wiped that disk entirely --
Elasticsearch included, not just CALDERA. This is the predicted
recurrence of an already-identified, still-unresolved gap.

**Fixed tonight:** Fleet Server itself (new token, recreated
fleet-server-policy).

**Not fixed tonight:** linux-workstation-policy and
linux-webserver-policy, with their Elastic Defend integrations.
Recreating these via raw API calls was judged too risky to guess
blind -- Elastic Defend's integration config is considerably more
complex than a basic agent policy (the "Complete EDR preset" Kibana's
UI constructs internally). Decided to recreate via Kibana UI next
session (same as originally done), then capture the real, working
JSON via GET and use it to build a stateless provisioning script --
same pattern as ensure-caldera-abilities.sh, applied to Fleet
policies.

**The actual fix that would prevent this whole category of recurrence:
a separate, persistent disk for Docker volumes, independent of the
boot disk's lifecycle.** Flagged two sessions ago, still not built.
Every stateless-provisioning script (CALDERA abilities, and the
planned Fleet policy one) is a real, working mitigation per-symptom --
not a substitute for fixing the actual root cause.## Password extraction bug: docker compose log line prefix

Following up on the --fresh/password-extraction work from the prior
session: the extraction step ran successfully (no warning), but the
published value failed to authenticate.

**Cause:** `docker compose logs` prefixes every line with the service
name (`caldera  | `). The multi-line password reconstruction captured
this prefix as part of the value -- e.g. `iMYkL0c...caldera|3oIFl...`
instead of the real, contiguous password.

**Fix:** strip the prefix before parsing:
```
docker compose logs caldera 2>&1 | sed -E 's/^caldera +\| ?//' | awk '...'
```

**Verified:** tested manually on control-node first -- clean
extraction, confirmed via a real login (302 with a genuine
API_SESSION cookie) -- before applying to the committed script. Then
verified end to end via a full terraform -replace: extraction,
publish, cleanup, and ability provisioning all completed with no
errors, no manual intervention.

## Fleet Server policy and target policies wiped -- same root cause as CALDERA

After the CALDERA --fresh fix, brought the full lab up for a normal
session. Fleet Server failed to start:
```
security_exception: failed to authenticate service account
[elastic/fleet-server] with token name [token-...]
```

**Diagnosis:**
1. Generated a new service account token directly against
   Elasticsearch -- succeeded, confirming Elasticsearch's security
   state no longer recognized the old one (stored, unchanged, in
   Secret Manager).
2. Published the new token, restarted Fleet Server -- authentication
   succeeded, but it then hung indefinitely: `"Waiting on policy with
   Fleet Server integration: fleet-server-policy"`.
3. `GET /api/fleet/agent_policies` returned zero policies. The
   Fleet Server container is hardcoded (via Terraform,
   FLEET_SERVER_POLICY_ID) to look for a policy literally named
   fleet-server-policy -- which no longer existed.
4. Recreated it via `POST /api/fleet/agent_policies` with that exact
   id. Fleet Server came up healthy immediately after.
5. Re-tried workstation-target enrollment -- failed with 401. Checked
   agent_policies again: still only fleet-server-policy exists.
   linux-workstation-policy and linux-webserver-policy, along with
   their Elastic Defend and System integrations, are also gone.

**Root cause: same as the CALDERA data loss two sessions ago, not a
new problem.** Docker's named volumes (including Elasticsearch's own
data) live on control-node's boot disk. Every terraform -replace
during the CALDERA investigation wiped that disk entirely --
Elasticsearch included, not just CALDERA. This is the predicted
recurrence of an already-identified, still-unresolved gap.

**Fixed tonight:** Fleet Server itself (new token, recreated
fleet-server-policy).

**Not fixed tonight, deliberate:** linux-workstation-policy and
linux-webserver-policy, with their Elastic Defend integrations.
Recreating these via raw API calls was judged too risky to guess
blind -- Elastic Defend's integration config is considerably more
complex than a basic agent policy (the "Complete EDR preset" Kibana's
UI constructs internally). Decided to recreate via Kibana UI next
session (same as originally done), then capture the real, working
JSON via GET and use it to build a stateless provisioning script --
same pattern as ensure-caldera-abilities.sh, applied to Fleet
policies.

**The actual fix that would prevent this whole category of 
"gets wiped after rebuild/lab instantiation":
a separate, persistent disk for Docker volumes, independent of the
boot disk's lifecycle.** 
Every stateless-provisioning script (CALDERA abilities, and the
planned Fleet policy one). Looking into whether stateles config setuo
at rebuild (aka policies/attacks) is better / more secure than
stateful and separate and persistant non-boot volume.
