# Contributing

## Development rules

- Keep the builder focused on upstream Mesa Turnip for Android ARM64.
- Do not add vendor or device patches without documenting the exact GPU ID, kernel behavior, and reason they are required.
- Do not silently switch from an official stable Mesa tag to `main` or a private fork.
- Keep generated artifacts out of commits.
- Do not add credentials, signing keys, device dumps containing private data, or production URLs.

## Before opening a pull request

Run the local checks available on your machine:

```bash
bash -n build.sh
```

If Docker is available, run a complete build and inspect:

```bash
unzip -l out/Mesa-Turnip-*.zip
cat out/SHA256SUMS.txt
```

Pull requests should explain the Mesa version-selection behavior, Android build configuration, packaging changes, and verification performed.
