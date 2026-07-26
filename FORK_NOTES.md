# goTelegram Clean

Private operational derivative of the audited goTelegram Pro snapshot.

## Provenance

- Source commit: `43ae73622c2652a87da6fb6f34043bf2b1dd329f`
- The original source snapshot did not include a license file.
- Keep this repository private unless redistribution rights are confirmed.
- The telemt engine is maintained and versioned independently.

## Product policy

- No advertising, affiliate links, donation prompts, or timed promotional UI.
- Telegram exposes routine operations only. Installation, mode changes,
  upstream updates, restore, and uninstall remain terminal-only actions.
- The web admin remains bound to loopback and is reached through an SSH tunnel.
- Deployments require a backup, syntax checks, automated tests, and a rollback
  copy of every replaced file.

## Initial clean release

- Removed promotional content from Telegram, the terminal installer, and web UI.
- Simplified the Telegram menu around status, links, diagnostics, backups,
  traffic, user keys, administrators, and the local web admin.
- Disabled stale Telegram callbacks for install, template/mode changes, restore,
  update, and uninstall so old messages cannot trigger those operations.
