---
name: jj-workflow
description: >-
  Reference guide for working with jj version control, including commits,
  splits, rebases, merge graphs, fetch recovery, and upstream squash merges.
  WHEN the user says - jj commit, jj split, jj rebase, jj fetch, squash
  merge recovery, stacked changes, repair jj graph.
---

# jj (Jujutsu) Workflow Guide

jj is a Git-compatible VCS used in some Fungible repos (StorageClient, FunOS).
It differs from Git in important ways.

## Key Concepts

- **Working copy is always a revision.** `@` is the current working revision.
  There's no staging area — all file changes are automatically part of `@`.
- **`jj new`** creates a new empty revision on top of `@`. Always do this
  after finishing a commit so future edits don't modify the previous commit.
- **`jj describe`** sets the commit message on `@` (or `-r REV`).
- **`jj commit`** = `jj describe` + `jj new` in one step.
- **Revisions are mutable.** You can edit any revision in the stack, not
  just the tip.

## Common Commands

### Viewing state
```bash
jj log --no-pager                          # Show revision graph
jj log --no-pager -r 'ancestors(@, 5)'     # Show last 5 ancestors
jj diff --stat --no-pager                  # Show working copy changes summary
jj diff --git --no-pager                   # Show working copy diff (unified/git format)
jj diff --git --no-pager -- path/to/file   # Diff a specific file
jj show REV --no-pager --stat              # Show a revision summary
jj show REV --no-pager --git               # Show a revision diff (readable format)
```

**IMPORTANT:** Always use `--git` with `jj diff` and `jj show` when viewing
actual diffs. The default diff format is jj's own format which is hard to
parse. `--git` produces standard unified diff output.

### Reading file content from a revision
```bash
jj file show -r REV path/to/file --no-pager
```
Note: `jj cat` does not exist. Use `jj file show`.

### Creating commits
```bash
# Describe current working copy and start a new revision:
jj describe -m 'commit message'
jj new

# Or in one step:
jj commit -m 'commit message'

# IMPORTANT: Always run `jj new` after finishing work on a revision,
# otherwise subsequent edits will modify the previous commit.
```

### Splitting commits by file
```bash
# Split specific files out of @ into a new commit:
jj split -r @ path/to/file1 path/to/file2 -m 'message for selected files' --no-pager

# The remaining changes stay in @ (or a new revision after @).
# Interactive split (opens editor — avoid in automation):
jj split -r @ --no-pager -i
```

### Squashing
```bash
jj squash                    # Squash @ into parent
jj squash -r REV             # Squash REV into its parent
jj squash --into REV         # Squash @ into a specific revision
jj squash --into REV -d      # Keep destination commit's message (no editor)
jj squash --into REV -m MSG  # Set a new message (no editor)
```

### Rebasing
```bash
jj rebase -r REV -d DEST     # Rebase single revision onto DEST
jj rebase -s REV -d DEST     # Rebase revision and all descendants
jj rebase -b REV -d DEST     # Rebase whole branch (REV + ancestors not in DEST)
```

### Inserting a revision into the middle of a stack (-A / -B)

Use `--insert-after/-A` and `--insert-before/-B` to place a revision
between existing commits without manually rebasing everything else.
Descendants of the target are automatically rebased on top.

```bash
# Insert K after L (K becomes L's child, L's old children move on top of K):
#   Before:  J ← L ← N       After:  J ← L ← K' ← N'
#            J ← K                    
jj rebase -r K -A L

# Insert K before L (K becomes L's parent, K sits between J and L):
#   Before:  J ← L ← N       After:  J ← K' ← L' ← N'
#            J ← K
jj rebase -r K -B L

# Combine -A and -B to insert between two specific commits:
jj rebase -r K -A J -B M     # K goes after J and before M
```

This is especially useful for reordering commits in a stack — e.g.,
moving a fix commit to sit right after the commit it logically belongs
with.

### Editing an earlier revision
```bash
jj edit REV                  # Make REV the working copy
# Make changes, then:
jj new                       # Return to tip
```

## Workflow: Splitting a Working Copy into Multiple Commits

When you have changes across many files in `@` and want logical commits:

```bash
# 1. Split out first logical group by file paths:
jj split -r @ path/a.c path/b.c -m 'first: description'

# 2. The remaining files are now in a new @ revision.
#    Split again if needed:
jj split -r @ path/c.py -m 'second: description'

# 3. Describe the final remaining changes:
jj describe -m 'third: description'

# 4. Start a clean revision for future work:
jj new
```

## Important Notes

- **Always use `--no-pager`** to avoid interactive pager issues in scripts
  and automation.
- **`jj show REV -- file`** does NOT work. Use `jj file show -r REV file`.
- **Revision IDs** are change IDs (short alphanumeric like `ptwsxsqv`), not
  commit hashes. Both work in `-r` arguments.
- **No `git add`** equivalent — all changes are automatically tracked.
- **`jj git push`** pushes to the Git remote. Use `-b branch` to specify
  which branch.
- **Conflicts** are recorded in the revision, not blocking. You can
  continue working and resolve later.

## Fetch post-check and auto-abandon recovery

A fetch that observes a squash merge, deleted branch, force update, or
rewritten remote bookmark can abandon the old local change. This may happen
even when the change has local descendants: jj can rebase those descendants
onto an earlier surviving ancestor, leaving their graph intact but removing
the parent content they depended on.

Fetch often reports at least some of the abandoned changes in its output.
Treat an abandonment message as a stop signal.

After a potentially destructive fetch, immediately inspect the graph:

```bash
jj git fetch --remote origin
jj status --no-pager
jj log --no-pager
```

Do not start resolving conflicts or rebasing if an expected local change
disappeared or a descendant acquired the wrong parent.

### Restore the pre-fetch graph

Find the operation immediately before the fetch:

```bash
jj op log
jj op restore <pre-fetch-operation-id>
```

Create local backup bookmarks for every relevant local instance of the change
that the upstream squash replaced:

```bash
jj bookmark create local-backup/change-1 -r L1
jj bookmark create local-backup/change-2 -r L2
```

Only the squash-replaced changes `L` need temporary bookmarks. Their ancestors
are protected by those bookmarks; the working copy and normal branch bookmarks
continue to protect the other legs.

Fetch again and repeat the immediate graph check:

```bash
jj git fetch --remote origin
jj status --no-pager
jj log --no-pager
```

## Reconcile local merges after an upstream squash merge

Use this workflow when a local change or stack `L` was squash-merged upstream,
while another local leg `T` and its descendants had already been merged or
stacked with `L`.

| Name | Meaning |
|---|---|
| `L` | Local bookmarked change or stack replaced by the squash merge. |
| `S` | Exact upstream squash commit containing the logical change from `L`. |
| `U` | Current upstream main tip, which contains `S` plus later changes. |
| `T` | Root of the other local leg that must survive. |
| `M` | Temporary reconciliation merge of `U` and `L`. |

Identify exact squash commit `S` from the PR to verify that it logically
replaces `L`. Use current `main@origin` as `U` so reconciliation also includes
unrelated changes that landed after the squash.

### 1. Create reconciliation merge `M`

```bash
jj new main@origin L -m 'temp: reconcile local change with upstream squash'
```

Resolve `M` toward upstream `U`. Upstream is canonical; `L` remains only to
keep the old graph connected and expose any differences.

Inspect the result:

```bash
jj diff --git --from main@origin --to M
```

This diff should be empty after resolution. Separately compare `L` with exact
squash commit `S`; if `S` omitted local changes, stop and decide explicitly
whether those changes should survive.

### 2. Rebase the surviving leg and its descendants

```bash
jj rebase -s T -d M
jj simplify-parents -s <new-tip>
```

Use `-s`, not a hand-written revision range. The intent is to move `T` and its
entire descendant subgraph, including old merge revisions and later stacked
work. jj can then simplify merge edges made redundant by the new ancestry.

This may expose conflicts caused by unrelated upstream changes that landed
after the original branch point. Resolve them as ordinary upstream conflicts;
do not reintroduce changes already represented by `S`.

### 3. Validate the reconstructed graph

```bash
jj log --no-pager
jj diff --git --from main@origin --to <new-tip>
```

The effective branch diff should contain the surviving leg and legitimate
integration resolutions, not a second copy of `L`.

When an old local result remains available, compare final trees:

```bash
jj diff --git --from <old-result> --to <new-tip>
```

Expected differences should be limited to unrelated upstream changes and
deliberate conflict resolutions.

### 4. Abandon superseded reconciliation ancestry

Preview the exact set first:

```bash
jj log --no-pager -r 'main@origin..M'
```

The set should contain only obsolete local instances of `L` and temporary
merge `M`. Once confirmed:

```bash
jj abandon 'main@origin..M'
jj simplify-parents -s <new-tip>
```

This rebases the surviving descendants directly onto upstream main and removes
the temporary reconciliation topology. `simplify-parents` removes any old-main
or squash parent that is already an indirect ancestor through another parent.

Never run the abandon command if the preview includes local work not
represented upstream.

### 5. Finalize

```bash
jj log --no-pager
jj diff --git --from main@origin --to <new-tip>
jj bookmark set <live-branch> -r <new-tip>
```

Keep `local-backup/*` bookmarks until the updated branch is pushed and
validated. Then remove them locally:

```bash
jj bookmark forget local-backup/change-1
```

Do not push backup bookmarks or remote deletions unless explicitly requested.

### Failure modes

- **Fetch reports abandoned changes:** restore the pre-fetch operation before
  doing anything else.
- **`M` differs from `U`:** resolve it toward upstream before continuing.
- **`S` differs materially from `L`:** the squash did not fully replace the
  local change; stop rather than silently dropping changes.
- **`jj rebase -s T -d M` moves unrelated work:** select a more precise root
  `T` and retry from the operation log.
- **The abandon preview contains desired work:** do not abandon it; correct the
  graph or use an explicit revision set.
- **Conflicts appear after abandoning `M`:** restore the prior operation if the
  conflict set is unexpected. If they are the original known merge conflicts,
  reapply the reviewed resolutions and run `simplify-parents` again.

## Commit Message Style

Follow the repo convention:
```
module: short summary of change

Longer description explaining the why. For multi-part changes,
use numbered lists. Reference the specific problem being solved.
```

Use single quotes carefully in `-m` arguments — escape with `'\''`:
```bash
jj describe -m 'hsnvme: fix vol_open deadlock

Changed fun_calloc_threaded to fun_alloc_forever since vol_open
doesn'\''t run in a threaded context.'
```

## Absorbing changes into earlier commits

`jj absorb` automatically matches hunks in the working copy to the
commits that last touched those lines, and amends each commit:
```bash
jj absorb
```

This is the **preferred way** to amend earlier commits when you have
small fixups across multiple files. Much faster than manual
`jj squash --from @ --into REV` for each file.

### When to use absorb vs squash

| Scenario | Use |
|---|---|
| Fixups to lines already in the stack | `jj absorb` — auto-routes each hunk |
| New files or new code blocks | `jj squash --into REV` — absorb can't match new content |
| Moving all of @ into a specific commit | `jj squash --into REV` |
| Combining two adjacent commits | `jj squash` (squashes @ into parent) |

### Typical workflow

```bash
# Make changes across several files
vim foo.rs bar.rs baz.c

# Absorb routes each hunk to the commit that last touched those lines
jj absorb

# Check the result
jj log --limit 5
```

### Limitations

- Only works for **modified lines** in existing files, not new files
- Hunks that can't be unambiguously matched to a single commit are left
  in the working copy — use `jj squash --into REV` for those
- Run `jj diff` after absorb to see if anything was left behind

## Editing mid-stack commits

```bash
jj edit REV            # make REV the working copy
# ... make changes ...
jj new                 # create empty commit on top and return to tip
```
Or to go back to a specific descendant:
```bash
jj new DESCENDANT_REV
```

## Squashing into a specific commit

```bash
jj squash               # squash @ into parent
jj squash --into REV    # squash @ into a specific ancestor
```
