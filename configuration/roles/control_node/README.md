# control_node

The role prepares the control host and installs core tools.

## Sudo user creation

The role creates a user with sudo privileges through a file in `/etc/sudoers.d`.

Configurable variables (defaults):

- `control_node_sudo_user_name` - name of the user to create (default: `devgru`)
- `control_node_sudo_user_shell` - user shell (default: `/bin/ash`)
- `control_node_sudo_group` - group granting sudo permissions (default: `wheel`)
- `control_node_sudo_user_passwordless` - whether to use `NOPASSWD` (default: `false`)
