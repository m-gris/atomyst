# Atomyst Release Automation

## Before Starting

1. **Initialize beads context:**
   ```bash
   cd /Users/marc/DATA_PROG/OCAML/atomyst
   bd prime
   ```

2. **Copy this plan to project:**
   ```bash
   cp /Users/marc/.claude/plans/staged-herding-allen.md docs/plans/release-automation.md
   ```

3. **Create beads epic and tasks:**
   ```bash
   bd create --title="Release Automation" --type=epic --priority=1
   # Then create child beads for each deliverable (see Implementation section)
   ```

---

## Goal

Enable one-line installation for end users:
```bash
curl -fsSL https://raw.githubusercontent.com/m-gris/atomyst/main/install.sh | bash
```

## Current State

- OCaml 5.0+ project, built with dune
- Dependencies: cmdliner, yojson, ppx_deriving, re
- Tree-sitter python.dylib is vendored (needs per-platform compilation)
- Existing `.github/workflows/publish.yml` is for Python (obsolete)
- Version hardcoded in `bin/main.ml` as "0.1.0"

## Deliverables

1. **GitHub Actions workflow** — Build binaries on tag push
2. **Install script** — Downloads correct binary for user's platform
3. **Version sync** — Single source of truth for version

---

## Implementation

### 1. Release Workflow (`.github/workflows/release.yml`)

**Trigger:** Push tag matching `v*` (e.g., `v0.2.0`)

**Matrix build:**
| Runner | Platform | Binary Name |
|--------|----------|-------------|
| `macos-14` | macOS arm64 | `atomyst-darwin-arm64` |
| `macos-13` | macOS x86_64 | `atomyst-darwin-x86_64` |
| `ubuntu-latest` | Linux x86_64 | `atomyst-linux-x86_64` |

**Steps per runner:**
1. Checkout code
2. Install OCaml via `ocaml/setup-ocaml@v3`
3. Install opam dependencies
4. Build tree-sitter python grammar (platform-specific)
5. Build atomyst binary with `dune build`
6. Rename binary with platform suffix
7. Upload artifact

**Final job:**
- Download all artifacts
- Create GitHub Release
- Attach binaries

### 2. Install Script (`install.sh`)

```bash
#!/bin/bash
set -euo pipefail

VERSION="${ATOMYST_VERSION:-latest}"
INSTALL_DIR="${ATOMYST_INSTALL_DIR:-$HOME/.local/bin}"

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

BINARY="atomyst-${OS}-${ARCH}"
# ... download from GitHub releases, chmod +x, move to INSTALL_DIR
```

### 3. Version Sync

**Approach:** Extract version from git tag in CI, pass to build via environment variable.

```yaml
# In workflow
- name: Get version from tag
  run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_ENV
```

The binary will show `atomyst 0.2.0` when built from tag `v0.2.0`.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `.github/workflows/release.yml` | Create — main release workflow |
| `.github/workflows/publish.yml` | Delete — obsolete Python workflow |
| `install.sh` | Create — curl-friendly installer |
| `bin/main.ml` | Modify — read version from `ATOMYST_VERSION` env var, fallback to "dev" |

---

## Tree-Sitter Compilation

The `python.dylib` (macOS) / `python.so` (Linux) needs platform-specific compilation.

**Current:** Pre-built `python.dylib` in repo root (macOS only)

**In CI:** Build from `vendor/tree-sitter-python/` on each platform:
```bash
cd vendor/tree-sitter-python
cc -shared -fPIC -o python.so src/parser.c src/scanner.c -I src
```

Or use tree-sitter CLI if available.

---

## Verification

After implementation:

1. **Tag a test release:**
   ```bash
   git tag v0.2.0-test
   git push origin v0.2.0-test
   ```

2. **Check GitHub Actions** — All 3 platform builds should succeed

3. **Check GitHub Releases** — Should have 3 binaries attached

4. **Test install script:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/m-gris/atomyst/main/install.sh | bash
   atomyst --version
   ```

5. **Test on each platform** (if available):
   - macOS arm64: Download and run
   - macOS x86_64: Download and run
   - Linux x86_64: Download and run

---

---

## Beads Breakdown

Create these beads under the "Release Automation" epic:

```bash
# Get epic ID after creating it
EPIC=$(bd create --title="Release Automation" --type=epic --priority=1 | grep -oE 'atomyst-[a-z0-9]+')

# Create child beads
bd create --title="Create GitHub Actions release workflow" --type=task --priority=1 --parent=$EPIC
bd create --title="Build tree-sitter per platform in CI" --type=task --priority=1 --parent=$EPIC
bd create --title="Create install.sh script" --type=task --priority=1 --parent=$EPIC
bd create --title="Pass version from git tag to binary" --type=task --priority=2 --parent=$EPIC
bd create --title="Delete obsolete Python publish workflow" --type=task --priority=2 --parent=$EPIC
bd create --title="Test release on all platforms" --type=task --priority=1 --parent=$EPIC
```

---

## Future Enhancements (Not This PR)

- Homebrew tap: `brew install m-gris/tap/atomyst`
- Shell completions (bash, zsh, fish)
- Checksum verification in install script
- Windows support (if demand exists)
