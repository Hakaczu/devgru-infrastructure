# Common role

Shared role applied to every managed host.

## Responsibilities
- Deploy Adeptus Mechanicus MOTD to /etc/motd.
- Run system package upgrades (Debian/Alpine).
- Ensure /opt/devgru/dotfiles exists for future automation hooks.
- Create a privileged user and grant sudo rights via /etc/sudoers.d.

## Privileged user settings
- `common_sudo_user_name` (default: `tech`)
- `common_sudo_user_shell` (default: `/bin/bash`)
- `common_sudo_group` (default: `wheel`)
- `common_sudo_user_passwordless` (default: `false`)
