# Contributing

Language: [中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

Thanks for helping improve VancePay.

## Development

This resource is loaded directly by FiveM/Qbox. There is no bundler or compile step.

Before opening a pull request, run one of the static checks:

```bash
./scripts/check.sh
```

```powershell
.\scripts\check.ps1
```

When adding a new Lua or browser JavaScript file, register it in both `fxmanifest.lua` and the check scripts.

## Pull Requests

- Keep changes focused and describe the player/admin-facing behavior.
- Mention SQL or config changes clearly.
- Include screenshots or clips for NUI and `lb-phone` UI changes.
- Do not commit secrets, server-specific convars, database dumps, or local runtime files.

## License

By contributing, you agree that your contribution is licensed under `AGPL-3.0-or-later`.
