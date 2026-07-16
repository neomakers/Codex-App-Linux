# Debian package builder

Build an offline, self-contained Ubuntu/Debian amd64 package from a tested
`codex-linux` runtime:

```bash
./packaging/debian/build-deb.sh
```

The artifact is written to `dist/`. It installs to `/opt/codex-app-linux` and
provides both `codex-app` and `codex` on the system `PATH`.

The package deliberately excludes `~/.codex`, including `auth.json`,
`config.toml`, caches, plugin state, logs, and every user's credentials. On a
target computer, sign in normally after installation, or provide that user's
own `CODEX_HOME` directory.

Install and remove:

```bash
sudo apt install ./codex-app-linux_*_amd64.deb
sudo apt remove codex-app-linux
```

`CODEX_APP_ROOT` can be set only for testing an extracted package tree. Normal
installations must use the package-managed `/opt/codex-app-linux` location.
