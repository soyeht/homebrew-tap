# soyeht/homebrew-tap

Homebrew tap for [theyOS](https://github.com/soyeht/theyos).

## Install

```bash
brew tap soyeht/tap
brew install theyos
```

## Requirements

- Apple Silicon (M1/M2/M3/M4)
- macOS 14 (Sonoma) or later
- ~100 GB free disk space

## First-time setup

```bash
soyeht start
```

This downloads macOS and creates the base VM image (~30 min first time).

## Uninstall

```bash
soyeht cleanup-homebrew
brew uninstall theyos
```

For a full purge, remove the user data and VMs too:

```bash
soyeht cleanup-homebrew --purge-data
brew uninstall theyos
```
