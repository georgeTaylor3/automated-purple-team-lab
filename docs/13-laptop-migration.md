# Laptop Migration

Quick checklist for standing up this project on a new laptop. Written
after moving from the MSI to the Asus for battery life.

## Before you start

- YubiKey physically in hand
- GitHub access (to register the new signing key)
- New laptop connected to the internet

## 1. Clone and bootstrap

```bash
git clone https://github.com/georgeTaylor3/automated-purple-team-lab.git
cd automated-purple-team-lab
chmod +x scripts/laptop-setup.sh
./scripts/laptop-setup.sh
```

This installs Docker, Terraform, Packer, jq, git. It pauses for the two
things it can't automate:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project purple-lab-48271
```

Press enter to continue once those are done. The script then:
- regenerates `shared/lab-vars.json` from Terraform outputs
- recreates all real `.pkrvars.hcl` files by copying the committed
  `.example.hcl` files (safe -- no secrets in them anymore)
- pulls `ELASTIC_PASSWORD` / `KIBANA_SYSTEM_PASSWORD` /
  `KIBANA_ENCRYPTION_KEY` directly from Secret Manager into a local `.env`

gcloud itself isn't installed by the script -- if missing, install from
https://cloud.google.com/sdk/docs/install first, then re-run the script.

## 2. Retrieve the SSH signing key from the YubiKey

The signing key is a resident/discoverable FIDO2 credential (as of
2026-09-01), so it can be pulled directly from the hardware -- no file
transfer needed.

```bash
ssh-keygen -K
```

With the YubiKey plugged in, enter the PIN when prompted. This should
recreate `id_ed25519_sk_git_signing_resident` and `.pub` in `~/.ssh/`.

Then point git at it:

```bash
git config --global user.signingkey ~/.ssh/id_ed25519_sk_git_signing_resident
git config --global gpg.format ssh
```

Confirm the `allowedSignersFile` setting carried over correctly (it's
part of global git config, not the repo, so check it explicitly):

```bash
git config --get gpg.ssh.allowedSignersFile
```

If it's unset or the file doesn't exist on the new laptop, recreate it:

```bash
mkdir -p ~/.config/git
echo "154277288+georgeTaylor3@users.noreply.github.com $(cat ~/.ssh/id_ed25519_sk_git_signing_resident.pub)" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

## 3. Verify signing works

```bash
git commit --allow-empty -S -m "test signing on new laptop"
git log --show-signature -1
```

Should show `Good "git" signature`, no "No principal matched" warning.
Delete the test commit once confirmed (`git reset --hard HEAD~1`,
only if it hasn't been pushed).

## 4. Test the local Docker stack

This is separate from the real `control-node` deployment in GCP --
purely local dev/testing. Fresh data every time, nothing carries over
from the old laptop.

```bash
docker compose up -d
docker compose ps
```

Should show `caldera`, `elasticsearch`, `kibana` (not `fleet-server` --
that one needs a real service token generated against this specific
local Elasticsearch, see `07-troubleshooting-log.md` for why).

## 5. Confirm GCP access to the real project

```bash
source scripts/set-lab-vars.sh
gcloud compute instances list --project="$PROJECT_ID"
```

Should show `control-node`, whatever its current state (stopped is
normal -- start it if you need to actually work on it).

## What does NOT need migrating

- Docker volumes / local test data -- disposable by design
- `docs/rbac-baseline.json` and `.sig` -- already committed to git
- Any Fleet Server service token -- lives in Secret Manager, fetched
  fresh by `control-node`'s own deploy script, not by this laptop
