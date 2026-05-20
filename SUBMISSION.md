# Distribute to Codex users

Codex's plugin system (launched March 2026) supports three marketplace types: the **Curated Plugin Directory** (OpenAI-managed, invite-only at the moment), **repo-scoped marketplaces**, and **personal marketplaces**. Public self-service submission to the Curated Directory is *"coming soon"* per OpenAI's docs, so the practical paths today are the repo-scoped and personal flows.

## Pre-flight checklist

- [ ] `.codex-plugin/plugin.json` exists with `name` (lowercase kebab-case)
- [ ] `displayName`, `version`, `description`, `author`, `license` all set
- [ ] `logo` field points to a committed file (we use `assets/logo.svg`)
- [ ] `skills/vastai/SKILL.md` has YAML frontmatter with `name` + `description`
- [ ] Every file under `prompts/` has frontmatter (`description`, `argument-hint`)
- [ ] `LICENSE` file at repo root
- [ ] Public Git repo
- [ ] `README.md` describes usage

## Users install from this repo today

End users add this repo as a marketplace source via the Codex CLI:

```bash
codex plugin marketplace add vast-ai/vast-codex-plugin
```

Supported source formats: GitHub shorthand (`owner/repo` or `owner/repo@ref`), HTTP(S) Git URLs, SSH Git URLs, local paths. Pin a Git ref with `--ref`; use `--sparse PATH` for sparse checkouts.

Then they install the plugin from the browser:

```bash
codex plugin   # opens the plugin browser; pick "Vast.ai" and Install
```

After installation, start a new thread and ask Codex to do something with Vast.ai — the skill auto-loads on relevant intent, or call a prompt explicitly (`/prompts:vast-status`, `/prompts:vast-launch OFFER=…`).

## Curated Plugin Directory (OpenAI-managed)

Currently invite-only. To request inclusion, monitor OpenAI's developer announcements at [developers.openai.com/codex/plugins](https://developers.openai.com/codex/plugins) and the [changelog](https://developers.openai.com/codex/changelog) for self-service publishing once it opens.

## Updating after distribution

For new versions:

1. Bump `version` in `.codex-plugin/plugin.json` (semver).
2. Push to `main`.
3. Users running `codex plugin marketplace refresh vast-ai/vast-codex-plugin` (or the global `refresh`) pull the new version.

## References

- [Codex Plugins docs](https://developers.openai.com/codex/plugins)
- [Build a plugin](https://developers.openai.com/codex/plugins/build)
- [Codex CLI reference (marketplace commands)](https://developers.openai.com/codex/cli/reference)
- [Codex changelog](https://developers.openai.com/codex/changelog)
