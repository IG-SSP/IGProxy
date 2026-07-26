# Deployment profiles

goTelegram Clean must not assume that TCP 443 is available on every host.
The configured public port is the source of truth for Telemt, Telegram links,
QR codes, the bot, and the admin dashboard.

## Direct 443

Use when TCP 443 is free. Telemt binds the public port directly. This is the
preferred censorship-resistance profile because the traffic resembles ordinary
HTTPS on the standard port.

## Alternate port

Use when TCP 443 already belongs to nginx, Xray, 3x-ui, or another production
service. Keep that service unchanged and bind Telemt to the first available
configured candidate, normally `8443`, `9443`, or `2053`.

This is the safe default for unattended or fleet deployments. The selected
port must be written to `config.json`, Telemt `server.port` and
`general.links.public_port`.

## Shared 443

Use only as an explicit advanced profile. A single L4 dispatcher owns public
TCP 443 and forwards connections to loopback listeners. Deployment requires a
backup, protocol/SNI compatibility checks, and a verified rollback for every
service already using 443.

The installer must never enable this profile or relocate an existing service
without an operator confirmation.

## Port selection policy

1. Detect the current owner of TCP 443.
2. If it is free, recommend Direct 443.
3. If another process owns it, recommend Alternate port.
4. Test candidates in order: `8443`, `9443`, `2053`.
5. Refuse an occupied custom port.
6. Expose Shared 443 as a separate advanced action.
