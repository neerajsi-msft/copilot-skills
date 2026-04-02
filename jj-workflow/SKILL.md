---
name: jj-workflow
description: "Reference guide for working with jj (Jujutsu) version control. Use when committing, splitting, rebasing, or managing change stacks with jj. WHEN: jj commit, jj split, jj new, jj describe, jj log, jj squash, jj rebase, version control workflow, commit changes, split commits."
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
