# Archive

This directory holds work that's no longer part of the active project, kept
for reference rather than deleted.

## packer-caldera-control-vm

The original CALDERA control node build: a full VM image (Packer +
`google_compute_instance`), installing CALDERA directly on Ubuntu via
systemd, alongside the OS.

This was fully built, debugged, and proven working end to end -- see
`docs/07-troubleshooting-log.md` for the free-trial mirror gap, the
Node/Vite version issue, and the first successful build.

Superseded by a containerized control node: CALDERA, Elastic, and the
future web controller now run as containers on one persistent VM, rather
than each service getting its own dedicated golden image. This is a better
fit for the project's ephemeral/low-cost goals and matches how many real
orgs actually separate VM-based endpoints from containerized backend
services.

Kept here rather than deleted since it represents real, working debugging
history that may be useful again -- either as a reference for the VM-based
pattern, or if the container approach is ever reconsidered.
