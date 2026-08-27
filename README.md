# basilica-audio/.github

Organisation-level assets shared by every repository in the [Basilica Audio](https://github.com/basilica-audio)
plugin suite.

| Path | What it is |
| --- | --- |
| [`profile/README.md`](profile/README.md) | The organisation profile page shown at github.com/basilica-audio |
| [`release-notes/`](release-notes/) | Composite action that publishes a release body from a repository's own `CHANGELOG.md` plus the suite-wide download, signing and install footer |
| [`docs/adr/`](docs/adr/) | Architecture decision records that bind the whole suite, rather than one plugin |

## `release-notes` — the shared release body

Each plugin's `release.yml` calls this action twice for a tag:

```yaml
- uses: basilica-audio/.github/release-notes@main
  with:
    tag: ${{ github.ref_name }}
    token: ${{ github.token }}
    include-assets: 'false'   # release-creating job: nothing is uploaded yet
```

```yaml
- uses: basilica-audio/.github/release-notes@main
  with:
    tag: ${{ github.ref_name }}
    token: ${{ github.token }}
    include-assets: 'true'    # after the platform jobs: renders the real asset list
```

The first call creates the release with the changelog section and the footer, so a failed platform
build still leaves a readable release page. The second rewrites the body once the archives are
attached, adding a Downloads table built from the assets that actually exist.

**A tag with no matching `## [x.y.z]` section in `CHANGELOG.md` fails the job.** That is deliberate:
publishing a release page that says nothing is the problem this action exists to solve. Set
`allow-missing-changelog-section: 'true'` if a particular tag genuinely has no entry.

The action is referenced at `@main` rather than pinned to a commit. Third-party actions in this
organisation are SHA-pinned, but this one lives inside the same trust boundary as the workflow that
calls it, and the point of having it in one repository is that a wording fix reaches all thirteen
plugins without thirteen pull requests.

See [`release-notes/action.yml`](release-notes/action.yml) for the full input list.
