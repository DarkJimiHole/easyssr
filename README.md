# EasySSR

EasySSR is an interactive Bash script for installing and managing `shadowsocks-rust` on Linux servers.

It focuses on a simple menu-driven workflow so you can deploy `ss-rust`, manage users, view configuration, and switch CN block rules without editing files by hand.

## Features

- Install the latest `shadowsocks-rust` release automatically
- Uninstall `shadowsocks-rust` and clean related files
- Add and delete users in multi-user config mode
- View server configuration and generate share links
- Enable or disable CN block ACL rules
- Shorcut `ssr` 

## Usage

```bash
bash <(curl -Ls https://raw.githubusercontent.com/DarkJimiHole/easyssr/main/install.sh)
```

## Menu

```text
1. Install ss-rust
2. Uninstall ss-rust
3. Add user
4. View configuration
5. Turn CN block on/off
6. Delete user
7. Uninstall script
0. Exit
```

## What The Script Manages

- `ssserver` binary: `/usr/local/bin/ssserver`
- shortcut command: `/usr/local/bin/ssr`
- config directory: `/etc/ssr`
- config file: `/etc/ssr/config.json`
- ACL file: `/etc/ssr/black_list.acl`
- systemd service: `/etc/systemd/system/ssr.service`

## Notes

- The project uses `2022-blake3-aes-128-gcm` by default.
- If password input is empty, the script generates a random base64 password automatically.
- Ports are validated before use.
- This repository stores the script as `install.sh`, while the installed runtime command is `ssr`.

## License

Use at your own risk.
