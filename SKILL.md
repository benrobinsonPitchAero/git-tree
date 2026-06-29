---
name: git-tree
description: Generate a self-contained interactive HTML visualization of a git repository's commit history — a GitKraken-style vertical lane graph with neon branch lanes, branch/tag pills, a HEAD marker, hover tooltips, a click-to-inspect side panel, and live search. Use when the user runs /git-tree, or asks to visualize, draw, graph, or see a picture of the git history, commit tree, branch structure, or lane graph of a repo.
---

# git-tree

Produces a single offline `git-tree.html` (D3 + commit data inlined) in the current
directory and opens it in the browser. Dark mode, glowing neon lanes, newest commit at top.

## Usage

Run the bundled script from the repository the user wants to visualize. Pass through
any flags the user gave. The script does all extraction, assembly, `.gitignore`
handling, and browser auto-open — do not hand-write the HTML.

```
bash ~/.claude/skills/git-tree/scripts/git-tree.sh [--depth N] [--branch <name>] [--no-gitignore]
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--depth N` | 150 | Cap on total commits across all branches combined |
| `--branch <name>` | all | Restrict to a single branch's history |
| `--no-gitignore` | off | Skip appending `git-tree.html` to `.gitignore` |

## Workflow

1. Make sure you are in the repo the user means (the script must run with that repo as
   the working directory). If unsure which directory, ask.
2. Map the user's request to flags (e.g. "just main, last 50" → `--branch main --depth 50`).
3. Run the script. It will:
   - Refuse cleanly if not a git repo or if the repo has 0 commits (writes nothing).
   - Write/overwrite `./git-tree.html`, add it to `.gitignore` (unless `--no-gitignore`),
     and open it in the default browser.
4. Relay the script's output. If auto-open failed (no `xdg-open`/`open`/`start`), tell the
   user the path to open manually.

## Notes

- The script is self-contained and deterministic; prefer it over generating HTML inline.
- The lane layout, colors, pills, tags, HEAD highlight, tooltip, side panel, and search
  are all computed client-side in the generated file's JavaScript. To change the visual
  design, edit `assets/template.html`.
- D3 v7 is vendored at `assets/d3.v7.min.js` and inlined at build time, so the output
  renders with no network access.
