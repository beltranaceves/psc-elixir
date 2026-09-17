# LaTeX / Overleaf version of the Project Proposal

This folder contains a LaTeX version of [`docs/project_proposal.md`](../project_proposal.md),
ready to compile on **Overleaf** (or any local LaTeX distribution).

## Files

| File | Purpose |
| --- | --- |
| `project_proposal.tex` | Main LaTeX document |
| `references.bib` | BibTeX bibliography (all references from the proposal) |

## Quick start on Overleaf

1. Go to <https://www.overleaf.com> and create a **Blank Project**.
2. Upload `project_proposal.tex` and `references.bib` (drag & drop, or copy-paste the contents).
3. Keep the default settings: compiler **pdfLaTeX**, bibliography tool **BibTeX**.
4. Click **Recompile** — the bibliography is generated automatically.

## Compiling locally

```bash
pdflatex project_proposal
bibtex project_proposal
pdflatex project_proposal
pdflatex project_proposal
```

## Notes

- Citations use `natbib` with the `plainnat` style (author–year, e.g. `(Aaen, 2008)`).
- DOIs are rendered as clickable links via the `doi` package.
- All references from the markdown are included in `references.bib`; add new ones there
  and cite them in the text with `\citep{key}`.
- The title page shows the supervisor/student emails as `mailto:` links.