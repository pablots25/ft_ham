# Releasing FT Ham

How a version goes from a branch to the App Store and a GitHub Release.

## Cadence

- **Patch releases (1.3.x)** every one to two weeks while there are fixes. App Review usually takes one to two days, so a short cycle gets fixes to operators fast.
- **Minor releases (1.x.0)** when features that sat behind a Remote Config flag are ready to turn on.
- A release goes out when the notes are written and the checks below pass, not on a fixed date.

## Branches and tags

The repository uses gitflow:

- `develop` collects finished `feature/*` and `fix/*` branches.
- `hotfix/X.Y.Z` (from `main`) or `release/X.Y.Z` (from `develop`) is where a version is prepared.
- When it ships, the branch is merged `--no-ff` into `main` and `develop`.
- Tags are annotated, have no `v` prefix (`1.3.2`), and sit on the `main` merge commit.
- `ft_ham_premium` gets the same tag on the commit that was built.

## Version files

- `VERSION` (repo root) holds the marketing version. It is the only version the CI can read, because `ft8_ham.xcodeproj` is not in git.
- `scripts/bump_version.sh X.Y.Z BUILD` updates the Xcode project (when present) and `VERSION` together.
- The release commit is `chore(release): bump version to X.Y.Z (build N)`.

## Release notes

Each release has notes written for operators, not a commit list.

1. Draft them from the commits since the last tag:

   ```bash
   scripts/release_notes.sh 1.3.2
   ```

   This writes `.github/RELEASE_NOTES.md` with the commits grouped as New, Improved and Fixed.

2. Rewrite the draft by hand:
   - Open with a thank you to new supporters and to anyone who reported or fixed a bug (callsign only if they agreed).
   - One short paragraph on what this version is about.
   - Sections by area (Decoding, Waterfall, CAT, Logbook and sync, Premium, Accessibility), each bullet saying what changes for the operator.
   - Reference issues as `(#123)`.
   - Keep the `Full Changelog` link at the end.
   - Use the same wording as the in-app What's New and the App Store "What's New" text.

3. Style rules (checked by `scripts/check_release_notes.py`):
   - American English.
   - No em dashes and no semicolons.
   - The first heading names the version (`# FT Ham 1.3.2`).
   - No `TODO` placeholders left over.

The file is committed with the release commit, so the notes travel with the tag. When the tag is pushed, the Release workflow creates the GitHub Release and uses this file as its body. If the file is missing or names another version, the generated commit list is kept and the workflow warns.

## Building and uploading

The Xcode project, `Assets.xcassets` and `GoogleService-Info.plist` are not in git, so builds are made on the release Mac, not in GitHub Actions.

```bash
scripts/release.sh 1.3.2 28 --dry-run
```

```bash
scripts/release.sh 1.3.2 28
```

The script asks before every step that publishes something. It:

1. Checks that the working tree is clean and `.github/RELEASE_NOTES.md` passes the style check.
2. Creates a detached worktree `../ft_ham-release-b<BUILD>` and copies the three ignored inputs into it.
3. Checks which branch `../ft_ham_premium` is on. If it is not the expected one, it builds against a detached premium worktree instead.
4. Sets the build number, archives into `~/Library/Developer/Xcode/Archives`, and exports with `destination=upload` to App Store Connect.
5. Zips the dSYMs next to the archive.

## Tagging

Once the build is approved and the release branch is merged into `main` and `develop`:

```bash
scripts/tag_release.sh 1.3.2 --premium-ref <premium sha printed by release.sh> --dry-run
```

It checks that `VERSION` and the notes on `main` match, creates annotated tags in both repositories, and asks before pushing them. Pushing the app tag starts the Release workflow.

If the export fails with "Failed to Use Accounts", sign in again under Xcode Settings, Accounts, and rerun with `--export-only`. If App Store Connect rejects the build number, bump it and run again.

## GitHub Actions

| Workflow | When | What |
|----|----|----|
| `ci.yml` | Pull requests and pushes to `develop` and `main` | String catalog check, release notes style, premium import guard, shell and workflow lint |
| `release.yml` | A pushed `X.Y.Z` tag, or a manual run | Checks the tag against `VERSION`, runs the strict string check, creates the GitHub Release with the hand-written notes |

The string check only warns on pull requests. On a release tag, missing translations or strings still marked `new` stop the release.

## Checklist

- [ ] All fixes merged into `hotfix/X.Y.Z` or `release/X.Y.Z`
- [ ] Unit tests pass locally on the default simulator
- [ ] New features ship with their flag off in Release
- [ ] What's New updated (and flagged items carry their `flag` key)
- [ ] `scripts/bump_version.sh X.Y.Z N`
- [ ] `scripts/release_notes.sh X.Y.Z`, then rewritten by hand
- [ ] `python3 scripts/check_release_notes.py X.Y.Z`
- [ ] `scripts/release.sh X.Y.Z N` (archive and upload)
- [ ] TestFlight smoke test, then submit for review (phased release)
- [ ] Merge into `main` and `develop`, then `scripts/tag_release.sh X.Y.Z`
- [ ] Check the GitHub Release page
