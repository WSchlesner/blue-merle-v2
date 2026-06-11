# Releasing blue-merle-v2

How versions, tags, GitHub releases, and the two CI workflows fit together,
plus a reference of every git/`gh` command involved.

## How a release works

The version lives in **two files**, and both must match the git tag:

| File | Line |
|---|---|
| `build-ipk.sh` | `PKG_VERSION=1.0.0` |
| `Makefile` | `PKG_VERSION:=1.0.0` |

Pushing a tag matching `v*.*.*` (e.g. `v1.0.1`) triggers both workflows:

| Workflow | Build path | Release asset |
|---|---|---|
| `build.yml` (Build Script) | `build-ipk.sh`, bundles the pre-compiled touch daemon | `blue-merle-v2_<ver>-Script-Release.ipk` |
| `sdk-build.yml` (Build SDK) | OpenWrt 23.05.4 SDK, compiles everything from source | `blue-merle-v2_<ver>-SDK-Release.ipk` |

Both workflows verify the tag against `PKG_VERSION` in both files and **fail
on purpose** if they disagree — bump the files first, then tag. The first
workflow to finish creates the GitHub release; the other attaches its IPK to
the same tag. GitHub adds the source `zip`/`tar.gz` automatically, so a
finished release has **4 assets**.

## Cutting a release

```sh
# 1. Bump the version in BOTH files
#      build-ipk.sh  ->  PKG_VERSION=1.0.1
#      Makefile      ->  PKG_VERSION:=1.0.1
git add build-ipk.sh Makefile
git commit -m "chore: bump version to 1.0.1"
git push origin main

# 2. Wait for the CI builds on main to go green, then tag
git tag v1.0.1
git push origin v1.0.1        # <- this triggers the release builds

# 3. When both workflows finish, edit the notes on the release page
#    (or: gh release edit v1.0.1 --notes-file notes.md)
```

Version bumps follow [semver](https://semver.org/): **patch** (1.0.x) for
fixes and docs, **minor** (1.x.0) for new features that stay
backwards-compatible, **major** (x.0.0) for breaking changes (e.g. config
format changes that require a reinstall).

## Rules for published tags

Once a tag has been pushed and the release is public:

- **Never move or delete it.** Users' downloads and checksums depend on it.
  If something is wrong, fix it on `main` and cut the next patch version.
- **Never force-push `main`.** Anyone who cloned would diverge.
- A workflow **re-run rebuilds the same commit** the tag points at — it never
  picks up new pushes. If the code changed, the fix is a new version, not a
  re-run. Re-runs are only useful for transient CI failures (network errors,
  runner hiccups).

## Command reference

### Tags

```sh
git tag                              # list tags
git tag v1.1.0                       # tag current HEAD
git tag v1.1.0 <commit-sha>          # tag a specific commit
git tag -a v1.1.0 -m "message"       # annotated tag (records tagger + date)
git push origin v1.1.0               # push one tag (triggers release workflows)
git show v1.1.0                      # which commit a tag points at
git tag -d v1.1.0                    # delete locally
git push origin --delete v1.1.0      # delete on GitHub (pre-publication only!)
```

### Releases (GitHub-side objects — use `gh` or the web UI)

```sh
gh release list
gh release view v1.0.0
gh release edit v1.0.0 --notes-file notes.md
gh release download v1.0.0           # fetch all assets
gh release delete v1.0.0             # delete release page+assets, keeps the tag
gh release delete v1.0.0 --cleanup-tag   # delete both (pre-publication only!)
```

### Workflow runs

```sh
gh run list --workflow=build.yml
gh run list --workflow=sdk-build.yml
gh run watch                         # live-tail the most recent run
gh run rerun <run-id>                # same commit only — see rules above
gh workflow run sdk-build.yml        # manual trigger on main (workflow_dispatch)
```

### Everyday inspection and recovery

```sh
git status                           # what's modified/staged
git log --oneline --graph -15        # recent history at a glance
git diff                             # unstaged changes
git diff --staged                    # what the next commit will contain
git reflog                           # every position HEAD has been; recovers "lost" commits
git stash / git stash pop            # shelve and restore uncommitted changes
git revert <sha>                     # safely undo a pushed commit (creates an inverse commit)
git reset --hard origin/main         # make local exactly match remote (DISCARDS local work)
```

## Troubleshooting

**Tag build fails with "Tag vX.Y.Z does not match PKG_VERSION".**
You tagged before bumping. Bump both files, commit, push, then move the tag
to the new commit — only safe because the release never finished publishing:

```sh
git tag -d v1.0.1
git push origin --delete v1.0.1
git tag v1.0.1
git push origin v1.0.1
```

**Release has fewer than 4 assets.**
One workflow failed or is still running — check the Actions tab. Once it
succeeds (or is re-run after a transient failure), its IPK attaches to the
existing release automatically.

**`build-ipk.sh` fails with "blue-merle-touch is unstripped".**
The bundled binary was rebuilt without `-s`. Use the rebuild command from the
README ("Rebuilding the touch daemon"), which strips at link time.
