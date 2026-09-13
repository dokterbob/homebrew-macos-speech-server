# dokterbob/macos-speech-server

Homebrew tap for [macos-speech-server](https://github.com/dokterbob/macos-speech-server) — a
local, on-device speech-to-text and text-to-speech server exposing OpenAI-compatible HTTP
endpoints and a Wyoming protocol server for Home Assistant.

## Install

```sh
brew install dokterbob/macos-speech-server/macos-speech-server
brew services start macos-speech-server
```

On first start the server downloads speech models (roughly 700 MB with the default engines)
into `~/Library/Application Support/FluidAudio` and `~/.cache/fluidaudio`. This takes several
minutes and prints nothing at the default `log_level` (`notice`); set `log_level: info` to
watch progress.

The server is ready when this returns audio:

```sh
curl -sf -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"tts-1","input":"Hello"}' -o /tmp/hello.wav
```

## Paths

| What | Where |
|------|-------|
| Configuration | `$(brew --prefix)/etc/speech-server/speech-server.yaml` |
| Logs | `$(brew --prefix)/var/speech-server/speech-server.log` |
| Working directory | `$(brew --prefix)/var/speech-server` |
| launchd label | `sh.brew.macos-speech-server` |

Upgrades never clobber your edits: an existing `speech-server.yaml` is kept and the new
upstream example is written alongside it as `speech-server.yaml.default`.

After editing the configuration, run:

```sh
brew services restart macos-speech-server
```

## Running as a system service

`brew services start macos-speech-server` installs a per-user LaunchAgent that starts at
login. To start at boot instead, under a dedicated role account:

```sh
# pick an unused UID in 450-499: dscl . -list /Users UniqueID | awk '$2 >= 450 && $2 <= 499'
sudo sysadminctl -addUser _speech-server -fullName "Speech Server" -UID 450 -roleAccount
sudo dscl . -create /Users/_speech-server NFSHomeDirectory "$(brew --prefix)/var/speech-server"
sudo mkdir -p "$(brew --prefix)/var/speech-server"
sudo chown -R _speech-server "$(brew --prefix)/var/speech-server"
brew services stop macos-speech-server 2>/dev/null || true
sudo brew services start macos-speech-server --sudo-service-user _speech-server
```

Do not run both services at once — they share ports 8080 and 10300. In system mode the
working directory (which also holds the log) is owned by `_speech-server`; to switch back to
the per-user service, `sudo brew services stop macos-speech-server` and hand the directory back
with `sudo chown -R "$(id -un)" "$(brew --prefix)/var/speech-server"` first.

## Documentation

Full configuration reference, API documentation and Home Assistant setup live in the
upstream repository: <https://github.com/dokterbob/macos-speech-server>.

## Maintainers

### Publishing bottles

1. Open a pull request against this tap. The `brew test-bot` workflow (`.github/workflows/tests.yml`)
   builds the formula and uploads the resulting bottles as a workflow artifact.
2. Once the PR is green, run the **`brew pr-pull`** workflow (`.github/workflows/publish.yml`)
   from the Actions tab, passing the pull request number (and optionally the expected head
   commit SHA). It downloads the bottle artifacts, commits the updated `bottle do` block, and
   pushes to `main`.
3. The bottles themselves are uploaded to this repository's GitHub Releases, which is where
   `brew install` fetches them from.

Note that `--skip-new` is passed to `brew test-bot --only-formulae`: the "new formula"
notability audit would otherwise fail this tap's formula.

### Bumping to a new version

```sh
brew bump-formula-pr --version=X.Y.Z dokterbob/macos-speech-server/macos-speech-server
```

(There is no `--tap` option; pass the fully qualified formula name instead.)

### Autobump CI caveat

`.github/workflows/autobump.yml` opens version-bump PRs on a schedule using the default
`GITHUB_TOKEN`. **Pull requests opened with `GITHUB_TOKEN` do not trigger other workflows**,
so those PRs arrive without any `brew test-bot` run and therefore without bottles.

Two ways around it:

- Create a fine-grained personal access token with **Contents: write** and
  **Pull requests: write** on this repository, store it as the repository secret
  `HOMEBREW_BUMP_TOKEN`, and use it in `autobump.yml` as `HOMEBREW_GITHUB_API_TOKEN`
  instead of `secrets.GITHUB_TOKEN`.
- Or simply close and reopen the autobump PR by hand, which does trigger CI.
