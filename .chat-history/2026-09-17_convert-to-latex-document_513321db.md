# Convert to LaTeX document

| | |
|---|---|
| **Created** | 2026-09-17 18:00:34 |
| **Last Message** | 2026-09-17 18:00:34 |
| **Model** | DeepSeek V4 Flash |
| **Mode** | agent |
| **User** | Unknown |
| **Session ID** | `513321db-adf5-442c-81db-f478924c528a` |

---

## User

*2026-09-17 18:01:03*

Im interested in transforming this into a latex/overleaf document that i can quickly render with a webpage service

## Assistant (opencodego/deepseek-v4-flash)

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service (like Overleaf).

Let me first read the project proposal document to understand its full content, then create a LaTeX version.

Let me read the file first.

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/docs/project_proposal.md)**

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu &

</details>

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu & Chen 2021 - A Systematic Review of Visual Representations

Plus frameworks/libraries:
- Elixir
- Phoenix
- Delta CRDTs
- LiveView

For the LaTeX document, I should use:
- `article` class or maybe `report` for a more structured document
- `biblatex` with `biber` (Overleaf supports this well) or traditional `natbib`/`bibtex`
- Actually

</details>

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu & Chen 2021 - A Systematic Review of Visual Representations

Plus frameworks/libraries:
- Elixir
- Phoenix
- Delta CRDTs
- LiveView

For the LaTeX document, I should use:
- `article` class or maybe `report` for a more structured document
- `biblatex` with `biber` (Overleaf supports this well) or traditional `natbib`/`bibtex`
- Actually, for Overleaf compatibility, both work. `biblatex` with `biber` is modern and works well on Overleaf. But `natbib` with `bibtex` is more universally compatible. Let me use `biblatex` since Overleaf handles it well, or actually let me think...

Overleaf supports both. The safest and most common approach is `natbib` + `bibtex` since it doesn't require changing the compiler settings. But `biblatex` is more modern. Overleaf's default is pdfLaTeX with bibtex. If I use biblatex, I need biber. Overleaf supports biber but the user needs to change the setting.

Actually, let me use `biblatex` with `biber` and note in the README that they need to set the compiler to biber. Or I could use natbib to keep it simple. Hmm.

Let me go with `biblatex` + `biber` since it's the modern standard and Overleaf makes it easy (just change the "BibTeX" dropdown to "Biber"). Actually, to minimize friction, maybe natbib is better. Let me think about what's best for the user...

The user wants to "quickly render with a webpage service". The least friction approach: pdfLaTeX + natbib + bibtex works out of the box on Overleaf with zero configuration. Let me go with that. Actually, biblatex is nicer for author-year citations with proper formatting. But natbib with a good style like `apalike` or `plainnat` works fine too.

Hmm, let me use `biblatex` with `style=authoryear` and `biber` — it's the modern approach and Overleaf supports it with one dropdown change. I'll document it clearly. Actually, you know what, let me reconsider once more.

The user said "quickly render with a webpage service". There are also services like:
- Overleaf
- LaTeX.Online
- Papeeria
- ShareLaTeX (now Overleaf)

For maximum compatibility with minimal setup, I'll go with `natbib` + `bibtex` + `plainnat` style. This works out of the box on Overleaf with pdfLaTeX. No compiler changes needed. This is the most frictionless.

Wait, but actually there's a subtlety: with natbib, I need to use `\citep` and `\citet` commands. That's fine.

Let me design the document:

```latex
\documentclass[11pt,a4paper]{article}

% Packages
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{geometry}
\usepackage{enumitem}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{titlesec}
\usepackage{parskip} % or setspace
\usepackage{natbib}
\usepackage{url}
...
```

Structure:
1. Title block (custom, not \maketitle necessarily, or use \maketitle with custom titlepage)
2. Project Summary (Abstract)
3. Background
4. Project Goals
5. Functional Requirements
   - 1. Core Tooling for VITs
   - 2. Collaborative Workspaces
   - 3. Delta Model & Versioning
   - 4. Analytics & Interaction Telemetry
   - 5. Insights & Content Analysis
6. Non-Functional Requirements
7. Deliverables
8. Future Work
9. References

I'll create:
- `docs/latex/project_proposal.tex` (main file)
- `docs/latex/references.bib` (bibliography)
- `docs/latex/README.md` (instructions for Overleaf)

Actually, maybe I should put it in a dedicated folder like `docs/latex/` or `report/`. Let me use `docs/latex/`.

Let me also think about whether to use `\citep`/`\citet` inline citations in the text. The markdown has inline citations like "(Aaen, 2008; Aaen, 2012)". I should convert these to proper LaTeX citations using `\citep{aaen2008essence, aaen2012essence}` etc. This makes the document much more professional and the bibliography properly formatted.

Let me map the citations:
- "Building on the *Essence* approach to software innovation (Aaen, 2008; Aaen, 2012)" → `\citep{aaen2008, aaen2012}`
- "Business Model Canvas (Osterwalder & Pigneur, 2010)" → `\citep{osterwalder2010}`
- "Lean Canvas (Maurya, 2012)" → `\citep{maurya2012}`
- "Design Principle Canvas (Schoormann et al., 2023)" → `\citep{schoormann2023}`
- "digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)" → `\citep{roschnik2024, avdiji2020}`
- "collaborative visual analytics (Chen et al., 2020; Chen et al., 2021; Kolloffel et al., 2011; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, kolloffel2011, hu2021}`
- "visual inquiry for sharing contextual knowledge (Sandberg, 2011)" → `\citep{sandberg2011}`
- "Presence, awareness, and representational guidance follow findings ... (Kolloffel et al., 2011; Chen et al., 2020; Chen et al., 2021)" → `\citep{kolloffel2011, chen2020, chen2021}`
- "Event models and visual representations ... (Chen et al., 2020; Chen et al., 2021; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, hu2021}`
- "Content-level coherence builds on design theory ... (Avdiji et al., 2020) and canvas-based guidance ... (Schoormann et al., 2023)" → `\citep{avdiji2020, schoormann2023}`

For the "Examples of existing tools in literature" list, I can keep them as a list with citations.

For frameworks and libraries, I'll add them as @misc or @online entries:
- Elixir: @online
- Phoenix: @online
- Delta CRDTs: @online (GitHub repo)
- LiveView: @online

Now, for the BibTeX entries, let me write them carefully:

```bibtex
@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  volume  = {17},
  number  = {5},
  pages   = {543--551},
  doi     = {10.1057/ejis.2008.43}
}
```

Hmm, I don't know the exact volume/pages. Let me not fabricate details. I'll include what's known: author, title, year, journal, doi. For the DOI, I can use the `doi` field which natbib/plainnat will render as a URL if hyperref is loaded. Actually plainnat doesn't render doi field by default. Let me use `url` field with the doi link instead, or use `\usepackage{doi}`. Hmm.

Actually, with natbib + plainnat, the `doi` field is not printed. To keep it simple and correct, I'll put the DOI in the `url` field or use the `doi` package. Let me use the `doi` package which converts doi fields to clickable links. That's clean.

Actually, let me reconsider: `\usepackage{doi}` works with natbib and prints DOIs as links. Good.

For Aaen 2012 "Essence: Team-Based Software Innovation" — this appears to be a book or report. I'll make it @

</details>

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu & Chen 2021 - A Systematic Review of Visual Representations

Plus frameworks/libraries:
- Elixir
- Phoenix
- Delta CRDTs
- LiveView

For the LaTeX document, I should use:
- `article` class or maybe `report` for a more structured document
- `biblatex` with `biber` (Overleaf supports this well) or traditional `natbib`/`bibtex`
- Actually, for Overleaf compatibility, both work. `biblatex` with `biber` is modern and works well on Overleaf. But `natbib` with `bibtex` is more universally compatible. Let me use `biblatex` since Overleaf handles it well, or actually let me think...

Overleaf supports both. The safest and most common approach is `natbib` + `bibtex` since it doesn't require changing the compiler settings. But `biblatex` is more modern. Overleaf's default is pdfLaTeX with bibtex. If I use biblatex, I need biber. Overleaf supports biber but the user needs to change the setting.

Actually, let me use `biblatex` with `biber` and note in the README that they need to set the compiler to biber. Or I could use natbib to keep it simple. Hmm.

Let me go with `biblatex` + `biber` since it's the modern standard and Overleaf makes it easy (just change the "BibTeX" dropdown to "Biber"). Actually, to minimize friction, maybe natbib is better. Let me think about what's best for the user...

The user wants to "quickly render with a webpage service". The least friction approach: pdfLaTeX + natbib + bibtex works out of the box on Overleaf with zero configuration. Let me go with that. Actually, biblatex is nicer for author-year citations with proper formatting. But natbib with a good style like `apalike` or `plainnat` works fine too.

Hmm, let me use `biblatex` with `style=authoryear` and `biber` — it's the modern approach and Overleaf supports it with one dropdown change. I'll document it clearly. Actually, you know what, let me reconsider once more.

The user said "quickly render with a webpage service". There are also services like:
- Overleaf
- LaTeX.Online
- Papeeria
- ShareLaTeX (now Overleaf)

For maximum compatibility with minimal setup, I'll go with `natbib` + `bibtex` + `plainnat` style. This works out of the box on Overleaf with pdfLaTeX. No compiler changes needed. This is the most frictionless.

Wait, but actually there's a subtlety: with natbib, I need to use `\citep` and `\citet` commands. That's fine.

Let me design the document:

```latex
\documentclass[11pt,a4paper]{article}

% Packages
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{geometry}
\usepackage{enumitem}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{titlesec}
\usepackage{parskip} % or setspace
\usepackage{natbib}
\usepackage{url}
...
```

Structure:
1. Title block (custom, not \maketitle necessarily, or use \maketitle with custom titlepage)
2. Project Summary (Abstract)
3. Background
4. Project Goals
5. Functional Requirements
   - 1. Core Tooling for VITs
   - 2. Collaborative Workspaces
   - 3. Delta Model & Versioning
   - 4. Analytics & Interaction Telemetry
   - 5. Insights & Content Analysis
6. Non-Functional Requirements
7. Deliverables
8. Future Work
9. References

I'll create:
- `docs/latex/project_proposal.tex` (main file)
- `docs/latex/references.bib` (bibliography)
- `docs/latex/README.md` (instructions for Overleaf)

Actually, maybe I should put it in a dedicated folder like `docs/latex/` or `report/`. Let me use `docs/latex/`.

Let me also think about whether to use `\citep`/`\citet` inline citations in the text. The markdown has inline citations like "(Aaen, 2008; Aaen, 2012)". I should convert these to proper LaTeX citations using `\citep{aaen2008essence, aaen2012essence}` etc. This makes the document much more professional and the bibliography properly formatted.

Let me map the citations:
- "Building on the *Essence* approach to software innovation (Aaen, 2008; Aaen, 2012)" → `\citep{aaen2008, aaen2012}`
- "Business Model Canvas (Osterwalder & Pigneur, 2010)" → `\citep{osterwalder2010}`
- "Lean Canvas (Maurya, 2012)" → `\citep{maurya2012}`
- "Design Principle Canvas (Schoormann et al., 2023)" → `\citep{schoormann2023}`
- "digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)" → `\citep{roschnik2024, avdiji2020}`
- "collaborative visual analytics (Chen et al., 2020; Chen et al., 2021; Kolloffel et al., 2011; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, kolloffel2011, hu2021}`
- "visual inquiry for sharing contextual knowledge (Sandberg, 2011)" → `\citep{sandberg2011}`
- "Presence, awareness, and representational guidance follow findings ... (Kolloffel et al., 2011; Chen et al., 2020; Chen et al., 2021)" → `\citep{kolloffel2011, chen2020, chen2021}`
- "Event models and visual representations ... (Chen et al., 2020; Chen et al., 2021; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, hu2021}`
- "Content-level coherence builds on design theory ... (Avdiji et al., 2020) and canvas-based guidance ... (Schoormann et al., 2023)" → `\citep{avdiji2020, schoormann2023}`

For the "Examples of existing tools in literature" list, I can keep them as a list with citations.

For frameworks and libraries, I'll add them as @misc or @online entries:
- Elixir: @online
- Phoenix: @online
- Delta CRDTs: @online (GitHub repo)
- LiveView: @online

Now, for the BibTeX entries, let me write them carefully:

```bibtex
@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  volume  = {17},
  number  = {5},
  pages   = {543--551},
  doi     = {10.1057/ejis.2008.43}
}
```

Hmm, I don't know the exact volume/pages. Let me not fabricate details. I'll include what's known: author, title, year, journal, doi. For the DOI, I can use the `doi` field which natbib/plainnat will render as a URL if hyperref is loaded. Actually plainnat doesn't render doi field by default. Let me use `url` field with the doi link instead, or use `\usepackage{doi}`. Hmm.

Actually, with natbib + plainnat, the `doi` field is not printed. To keep it simple and correct, I'll put the DOI in the `url` field or use the `doi` package. Let me use the `doi` package which converts doi fields to clickable links. That's clean.

Actually, let me reconsider: `\usepackage{doi}` works with natbib and prints DOIs as links. Good.

For Aaen 2012 "Essence: Team-Based Software Innovation" — this appears to be a book or report. I'll make it @book or @misc. The markdown doesn't give a publisher. I'll use @misc with note or just @book without publisher. Let me use @misc to be safe... Actually, since it's cited as a book-like work, @book is fine but I don't have publisher info. Let me use @misc with a note. Hmm, actually for the report, I'll keep it simple: @book with just author/title/year, and note "Publisher information not specified in source document" — no, that's ugly. Let me just use @misc.

Actually, let me think about what's cleanest. I'll use:

```bibtex
@misc{aaen2012essence,
  author = {Aaen, Ivan},
  title  = {Essence: Team-Based Software Innovation},
  year   = {2012}
}
```

For books:
```bibtex
@book{osterwalder2010business,
  author    = {Osterwalder, Alexander and Pigneur, Yves},
  title     = {Business Model Generation},
  year      = {2010},
  publisher = {Wiley},
  url       = {https://www.strategyzer.com/books/business-model-generation}
}

@book{maurya2012running,
  author    = {Maurya, Ash},
  title     = {Running Lean},
  year      = {2012},
  publisher = {O'Reilly Media},
  url       = {https://leanspark.ai/leancanvas}
}
```

For conference papers:
```bibtex
@inproceedings{sandberg2011visual,
  author    = {Sandberg, F},
  title     = {Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge},
  booktitle = {Nordic Design Research Conference},
  year      = {2011},
  doi       = {10.21606/nordes.2011.028}
}

@article{schoormann2023guiding,
  author  = {Schoormann, Thorsten and M{\"o}ller, Frederik and Di Maria, Marco and Gro{\ss}e, N},
  title   = {Guiding Design Principle Projects: A Canvas for Young Design Science Researchers},
  journal = {Journal of Information Systems Education},
  year    = {2023},
  doi     = {10.62273/wkbc7575}
}

@inproceedings{roschnik2024approaching,
  author    = {Roschnik, A and Jaccard, D and Monnier, S and Missonier, S},
  title     = {Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform},
  booktitle = {ICIS Proceedings},
  year      = {2024}
}

@article{avdiji2020design,
  author  = {Avdiji, Hazbi and Elikan, Dina and Missonier, St{\'e}phanie and Pigneur, Yves},
  title   = {A Design Theory for Visual Inquiry Tools},
  journal = {Journal of the Association for Information Systems},
  year    = {2020},
  volume  = {21},
  number  = {6},
  doi     = {10.17705/1jais.00617}
}
```

Hmm, I need to be careful not to fabricate volume/number info. For Avdiji 2020, the DOI is 10.17705/1jais.00617. I know the JAIS article... I shouldn't fabricate. Let me include only what's in the source: author, title, journal, year, doi. That's safe.

For the collaboration papers:
```bibtex
@article{kolloffel2011comparing,
  author  = {Kolloffel, Bas and Eysink, Tessa H. S. and de Jong, Ton},
  title   = {Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning},
  journal = {International Journal of Computer-Supported Collaborative Learning},
  year    = {2011},
  volume  = {6},
  number  = {2},
  pages   = {223--251},
  doi     = {10.1007/s11412-011-9110-3}
}
```

Hmm, again, I know this paper has volume 6, pages 223-251, but I shouldn't fabricate. Let me just include author, title, journal, year, doi. Actually, the DOI is given in the source, so I'll include that. Volume/pages I'll omit to avoid fabrication.

```bibtex
@article{chen2020collaborative,
  author  = {Chen, Lin and Liang, Hai-Ning and Lu, Feiyu and Papangelis, Konstantinos and Man, Ka Lok and Yue, Yong},
  title   = {Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices},
  journal = {Human-centric Computing and Information Sciences},
  year    = {2020},
  volume  = {10},
  doi     = {10.1186/s13673-020-00253-7}
}
```

Hmm, volume 10 is correct for this one (it's article 40 in volume 10). But again, to be safe, I'll omit volume. Actually, the DOI is enough.

```bibtex
@article{chen2021large,
  author  = {Chen, Lin and Liang, Hai-Ning and Wang, Junxiu and Qu, Yuxuan and Yue, Yong},
  title   = {On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks},
  journal = {Sensors},
  year    = {2021},
  volume  = {21},
  number  = {24},
  doi     = {10.3390/s21248403}
}
```

Again, I'll omit volume/number to be safe. Just author, title, journal, year, doi.

```bibtex
@article{hu2021systematic,
  author  = {Hu, L and Chen, G},
  title   = {A Systematic Review of Visual Representations for Analyzing Collaborative Discourse},
  journal = {Educational Research Review},
  year    = {2021},
  doi     = {10.1016/j.edurev.2021.100403}
}
```

For frameworks:
```bibtex
@online{elixir,
  author = {Elixir Team},
  title  = {Elixir},
  year   = {2026},
  url    = {https://elixir-lang.org}
}

@online{phoenix,
  author = {Phoenix Framework},
  title  = {Phoenix},
  year   = {2026},
  url    = {https://www.phoenixframework.org}
}

@online{delta_crdt,
  author = {Kraan, Derek},
  title  = {Delta CRDTs},
  year   = {2026},
  url    = {https://github.com/derekkraan/delta_crdt_ex}
}

@online{liveview,
  author = {Phoenix Framework},
  title  = {Phoenix LiveView},
  year   = {2026},
  url    = {https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView}
}
```

Note: `@online` requires natbib to handle it. plainnat handles @online? Actually, plainnat is a bibtex style, and @online entries are supported by newer bibtex styles. plainnat does support @online I believe (it's in the natbib distribution). Yes, plainnat supports @online.

Hmm wait, actually there might be an issue: plainnat.bst handles @online? Let me think. plainnat.bst is from the natbib package and it does handle @online and @electronic. Yes, it does.

Now for the LaTeX document itself. Let me write a clean, professional document:

```latex
\documentclass[11pt,a4paper]{article}

% ---- Packages ----
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{geometry}
\geometry{margin=2.5cm}
\usepackage{graphicx}
\usepackage{xcolor}
\usepackage{booktabs}
\usepackage{enumitem}
\usepackage{parskip}
\usepackage{microtype}
\usepackage{doi}
\usepackage[round]{natbib}
\usepackage[hidelinks]{hyperref}
\usepackage{titlesec}
```

Wait, `\usepackage{doi}` — the doi package. It works with natbib. Good.

For the title, I'll create a custom title block:

```latex
\begin{titlepage}
  \centering
  \vspace*{2cm}
  {\Huge\bfseries Developing a Configurable Platform for Collaborative Visual Inquiry Tools\par}
  \vspace{0.5cm}
  {\LARGE The Problem--Solution Canvas\par}
  \vspace{2cm}
  {\large 9th Semester Project Proposal\par}
  \vspace{1cm}
  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
    \textbf{Student:} & Beltran Aceves \\
  \end{tabular}
  \vfill
  {\large \today\par}
\end{titlepage}
```

Hmm, but the user might want to keep the emails. Let me include them with \href.

Actually, let me reconsider the structure. The original has:
- Title
- 9th Semester
- Supervisor/Student with emails
- Project Summary
- Background
- Project Goals
- Functional Requirements (1-5)
- Non-Functional Requirements
- Deliverables
- Future Work
- References

I'll structure it as:
- Title page
- Abstract (Project Summary)
- Background
- Project Goals
- Functional Requirements
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the "Examples of existing tools" lists, I'll use itemize environments.

For the industry tools with URLs, I'll use \href.

Let me also think about the "quickly render with a webpage service" part. The user wants to render this quickly. Options:
1. Overleaf — upload the .tex and .bib files, compile with pdfLaTeX + BibTeX
2. A local service

I'll create a README with instructions for Overleaf, including:
- Create a new project, upload files
- Compile with pdfLaTeX (default) and BibTeX
- The natbib approach needs no special compiler settings

Let me also consider: should I use `biblatex` instead? With biblatex, the user needs to switch the compiler to biber in Overleaf. That's one extra step. natbib + bibtex works out of the box. I'll go with natbib.

Actually, wait. Let me reconsider. Modern Overleaf projects default to pdfLaTeX with "BibTeX" as the bibliography tool. natbib + plainnat + bibtex works perfectly with zero configuration. 

Let me now also think about whether to include a `\tableofcontents`. For a proposal document, a TOC is nice. I'll include it.

Let me write the full LaTeX document now.

One more consideration: the em-dash in "Problem–Solution Canvas" — I'll use `Problem--Solution` in LaTeX.

Also "9th Semester" — I'll put it on the title page.

Let me draft the full .tex file:

```latex
% ============================================================================
%  Project Proposal: A Configurable Platform for Collaborative Visual
%  Inquiry Tools — The Problem–Solution Canvas
%
%  Compile with pdfLaTeX + BibTeX (works out of the box on Overleaf).
% ============================================================================
\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts -------------------------------------------------------
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{microtype}

% --- Page layout ------------------------------------------------------------
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt, itemsep=2pt, parsep=0pt}

% --- Graphics & colors ------------------------------------------------------
\usepackage{xcolor}
\usepackage{graphicx}

% --- Tables -----------------------------------------------------------------
\usepackage{booktabs}

% --- Hyperlinks & DOIs ------------------------------------------------------
\usepackage[hidelinks]{hyperref}
\urlstyle{same}
\usepackage{doi}

% --- Citations --------------------------------------------------------------
\usepackage[round]{natbib}
\bibliographystyle{plainnat}

% --- Section formatting -----------------------------------------------------
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}

% --- Metadata ---------------------------------------------------------------
\title{Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem--Solution Canvas}
\author{Beltran Aceves}
\date{9th Semester}

\begin{document}

% --- Title page -------------------------------------------------------------
\begin{titlepage}
  \centering
  \vspace*{1.5cm}

  {\Huge\bfseries Developing a Configurable Platform for\\[0.3em] Collaborative Visual Inquiry Tools\par}
  \vspace{0.6cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{2.5cm}

  {\large 9th Semester Project Proposal\par}

  \vspace{1.5cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{ivan@cs.aau.dk} \\[0.5em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{baceve25@student.aau.dk} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}

\tableofcontents
\newpage

% --- Project Summary --------------------------------------------------------
\section{Project Summary}
...
```

Wait, the emails in the original have typos: `ivan@cs.af` and `baceve25@stduent.aau.dk`. These are clearly typos in the markdown (the mailto links are `mailto:ivan@cs.af` and `mailto:baceve25@stduent.aau.dk`). The display text is `ivan@cs.aau.dk` and `baceve25@student.aau.dk`. I'll use the correct display emails: `ivan@cs.aau.dk` and `baceve25@student.aau.dk`.

Now the body content. Let me convert each section:

**Project Summary:**
```latex
\section{Project Summary}

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem--Solution Canvas (PSC), developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems.

The platform will therefore let users:
\begin{itemize}
  \item define and share canvas templates (e.g., PSC variants);
  \item instantiate collaborative canvas instances that load and synchronize in real time;
  \item explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, and supports visualizing and traversing versions;
  \item automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event stream datasets;
  \item analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.
\end{itemize}

Implemented as a web application using the Elixir/Phoenix/Postgres stack, the platform will provide CRDT-based real-time collaboration, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.
```

**Background:**
```latex
\section{Background}

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem--Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the \emph{Essence} approach to software innovation \citep{aaen2008essence,aaen2012essence}, the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as Strategyzer \citep{...}...
```

Hmm, for the industry platforms, they're websites, not citations. I'll use \href for them.

```latex
Existing industry platforms such as \href{https://www.strategyzer.com}{Strategyzer}, \href{https://miro.com}{Miro}, \href{https://www.mural.co}{MURAL}, \href{https://canvanizer.com}{Canvanizer}, \href{https://leanspark.ai/leancanvas}{Lean Canvas}, and \href{https://designthinking.ideo.com/}{IDEO Design Thinking Tools} provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time or whether canvas content remains coherent and up to date. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas \citep{osterwalder2010business}, Lean Canvas \citep{maurya2012running}, Design Principle Canvas \citep{schoormann2023guiding}, and recent work on digital inquiry platforms \citep{roschnik2024approaching,avdiji2020design} and collaborative visual analytics \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}, as well as visual inquiry for sharing contextual knowledge \citep{sandberg2011visual}. This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, fine-grained interaction tracing, and content-level insights into a unified research-oriented platform.
```

Then the two lists:

```latex
\subsection{Examples of Existing Tools in Literature}
\begin{itemize}
  \item \textbf{Business Model Canvas} --- Osterwalder, A., \& Pigneur, Y. (2010). \emph{Business Model Generation}. \citep{osterwalder2010business}
  \item \textbf{Lean Canvas} --- Maurya, A. (2012). \emph{Running Lean}. \citep{maurya2012running}
  \item \textbf{Design Principle Canvas} --- Schoormann, T., et al. (2023). \emph{Guiding Design Principle Projects: A Canvas for Young Design Science Researchers}. \citep{schoormann2023guiding}
  \item \textbf{Digital Inquiry Platform concepts} --- Roschnik, A., et al. (2024). \emph{Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform}. See also Avdiji et al. (2020). \citep{roschnik2024approaching,avdiji2020design}
  \item \textbf{Collaborative visual inquiry and analytics research} --- Chen, L., et al. (2020). \emph{Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices}. See also Chen et al. (2021); Kolloffel et al. (2011); Hu \& Chen (2021). \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}
  \item \textbf{Visual inquiry and contextual knowledge sharing} --- Sandberg, F. (2011). \emph{Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge}. \citep{sandberg2011visual}
\end{itemize}

\subsection{Examples of Existing Tools in Industry}
\begin{itemize}
  \item \href{https://www.strategyzer.com/library?type=Tools}{Strategyzer}
  \item \href{https://miro.com}{Miro}
  \item \href{https://www.mural.co/templates}{MURAL}
  \item \href{https://canvanizer.com}{Canvanizer}
  \item \href{https://leanspark.ai/leancanvas}{Lean Canvas}
  \item \href{https://designthinking.ideo.com/}{Design Thinking tools (IDEO U)}
\end{itemize}
```

**Project Goals:**
```latex
\section{Project Goals}

The project focuses on building the MVP:
\begin{itemize}
  \item Development of the main web application with VIT core features;
  \item Implementation of the delta-based versioning system: explicit milestones/versions/commits in a traversable tree, with visualization and recorded pivot/bifurcation rationale;
  \item Implementation of the insights system for analyzing canvas content (coherence, staleness, quality signals, with optional LLM-enabled insights);
  \item Implementation of the analytics engine (automatic capture of interaction events and metrics) to lay the foundation for later study.
\end{itemize}
```

**Functional Requirements:**
```latex
\section{Functional Requirements}

\subsection{Core Tooling for VITs}
Design and implement core tooling for building Visual Inquiry Tools (VITs). This includes:
\begin{itemize}
  \item defining canvas structure (cells, relations, semantics) and templates;
  \item editor UI and components for creating and editing cells;
  \item template persistence and instantiation of canvases.
\end{itemize}

\subsection{Collaborative Workspaces}
Develop workspaces for real-time collaboration on canvases. This includes:
\begin{itemize}
  \item real-time collaborative editing using CRDTs with live document loading and conflict-free merges;
  \item per-user presence and cursor indicators, plus inline comments and discussion threads;
  \item sharing, access control, and session management for team sessions.
\end{itemize}

Presence, awareness, and representational guidance follow findings on collaborative inquiry learning and engagement with shared visual tasks \citep{kolloffel2011comparing,chen2020collaborative,chen2021large}.

\subsection{Delta Model \& Versioning}
A PSC, or any other VIT instance, evolves continuously during collaborative real-time sessions. This fluid evolution is normal and expected, but teams also need to explicitly mark that they have reached a meaningful point in the progress of their project or canvas.

The delta system provides this intentional versioning layer, to:
\begin{itemize}
  \item let users create explicit milestones/versions/commits (snapshots) of the canvas at chosen moments;
  \item organize versions in a tree-like manner supporting linear history as well as branches for pivots, bifurcations, and parallel alternatives;
  \item visualize and traverse the version tree (timeline/tree view, diff/compare between versions, restore or fork from any version);
  \item record the reason for each pivot or bifurcation (decision rationale, reinterpretation note, author, timestamp, parent link(s));
  \item provide tools to annotate and group deltas/versions for later analysis.
\end{itemize}

\subsection{Analytics \& Interaction Telemetry}
The platform provides an analytics engine that automatically captures all kinds of events and metrics from users interacting with the system, so they can be analyzed later:
\begin{itemize}
  \item passively log interaction events (edits, navigation, presence, comments, version operations, insight views) with order, frequency/distribution, and metadata (who, when, where in the canvas, session/device context);
  \item expose exportable event streams and lightweight aggregation APIs for research use;
  \item enable studies of user archetypes, framing patterns, collaboration dynamics, and outcome correlations.
\end{itemize}

Event models and visual representations for collaborative discourse build on prior work in visual analytics and discourse analysis \citep{chen2020collaborative,chen2021large,hu2021systematic}.

\subsection{Insights \& Content Analysis}
Analyze the contents of a given PSC to support reflection and convergence, complementing the interaction-level analytics in Section~\ref{sec:analytics}:
\begin{itemize}
  \item detect cells deviating from the central theme or problem framing of the canvas;
  \item detect old/stale cells (e.g., untouched, superseded, or inconsistent with recent pivots/decisions);
  \item surface coherence and quality signals (e.g., contradictions, gaps, duplicates across cells);
  \item provide LLM-enabled insights where appropriate (e.g., summaries, suggestions, theme-drift explanations), designed as an optional, pluggable layer over deterministic heuristics so the platform remains usable without an LLM provider.
\end{itemize}

Content-level coherence builds on design theory for visual inquiry tools \citep{avdiji2020design} and canvas-based guidance for design projects \citep{schoormann2023guiding}.
```

I need to add a label to the analytics section: `\label{sec:analytics}`.

**Non-Functional Requirements:**
```latex
\section{Non-Functional Requirements}
\begin{itemize}
  \item The platform should be built using the Elixir/Phoenix stack for scalability and real-time capabilities.
  \item The system should be designed for extensibility to support future features and different types of VIT, including new insight detectors and LLM providers.
  \item The user interface should be intuitive and responsive to facilitate collaboration and ease of use, including support for both desktop and mobile devices.
  \item The platform should ensure data integrity and consistency during real-time collaboration, using CRDTs for conflict-free merging of changes.
  \item The analytics infrastructure should be designed to efficiently capture and store interaction data while minimizing performance overhead on the user experience.
  \item The insights system should run efficiently alongside editing (e.g., asynchronous/on-demand analysis) and keep LLM usage optional, privacy-aware, and clearly attributed, so canvases remain fully usable without external AI services.
  \item The system should be easy to deploy and maintain, with clear documentation for both users and developers.
\end{itemize}
```

**Deliverables:**
```latex
\section{Deliverables}
\begin{itemize}
  \item A working web application built with Elixir/Phoenix;
  \item Project documentation and deployment guide;
  \item Support for:
  \begin{itemize}
    \item configurable visual inquiry templates;
    \item collaborative canvas instances;
    \item delta-based pivot versioning;
    \item insights system for canvas content analysis (theme deviation, stale cells, coherence signals, with optional LLM-enabled insights);
    \item a basic analytics engine automatically capturing user interaction events and metrics, with exportable streams for later analysis;
  \end{itemize}
  \item A written report describing:
  \begin{itemize}
    \item design decisions;
    \item system architecture;
    \item and implications for supporting visual inquiry and innovation.
  \end{itemize}
\end{itemize}
```

**Future Work:**
```latex
\section{Future Work}

The following are out of scope for the MVP but are natural next steps once the core platform is in place.

\paragraph{Experiments on user behavior.}
Design and run studies using the analytics engine to look at patterns of use, problem framing, and solution development; such as user archetypes, framing patterns, collaboration dynamics, and how they relate to outcomes. This would also mean scaling up the analytics side: experiment tooling, aggregation APIs, and dataset exports for larger studies.

\paragraph{Non-table canvases.}
The MVP assumes table-like canvases made of cells. Later we want templates that are not grids at all: a background image or SVG with floating text inputs placed on top of it. This would support more visual or spatial VITs (maps, diagrams, annotated pictures) using the same collaboration, versioning, and analytics foundations.
```

**References:**
```latex
\section{References}
\bibliography{references}
```

Wait, I should organize the references. The original has subsections: Frameworks and Libraries, Core Concepts, Visual Inquiry Tools and Collaborative Inquiry, Collaboration Visual Analytics and Interaction Analysis. With a single .bib file and plainnat, the references will be alphabetical. That's fine and standard. I could add \nocite for all entries. Since I cite everything in the text, all entries will appear. Let me double check: do I cite all entries?

- aaen2008essence ✓ (Background)
- aaen2012essence ✓ (Background)
- osterwalder2010business ✓ (Background + literature list)
- maurya2012running ✓ (Background + literature list)
- schoormann2023guiding ✓ (Background + literature list + insights)
- roschnik2024approaching ✓ (Background + literature list)
- avdiji2020design ✓ (Background + literature list + insights)
- chen2020collaborative ✓ (Background + literature list + workspaces + analytics)
- chen2021large ✓ (Background + literature list + workspaces + analytics)
- kolloffel2011comparing ✓ (Background + literature list + workspaces)
- hu2021systematic ✓ (Background + literature list + analytics)
- sandberg2011visual ✓ (Background

</details>

<details>
<summary>💭 Thinking</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu & Chen 2021 - A Systematic Review of Visual Representations

Plus frameworks/libraries:
- Elixir
- Phoenix
- Delta CRDTs
- LiveView

For the LaTeX document, I should use:
- `article` class or maybe `report` for a more structured document
- `biblatex` with `biber` (Overleaf supports this well) or traditional `natbib`/`bibtex`
- Actually, for Overleaf compatibility, both work. `biblatex` with `biber` is modern and works well on Overleaf. But `natbib` with `bibtex` is more universally compatible. Let me use `biblatex` since Overleaf handles it well, or actually let me think...

Overleaf supports both. The safest and most common approach is `natbib` + `bibtex` since it doesn't require changing the compiler settings. But `biblatex` is more modern. Overleaf's default is pdfLaTeX with bibtex. If I use biblatex, I need biber. Overleaf supports biber but the user needs to change the setting.

Actually, let me use `biblatex` with `biber` and note in the README that they need to set the compiler to biber. Or I could use natbib to keep it simple. Hmm.

Let me go with `biblatex` + `biber` since it's the modern standard and Overleaf makes it easy (just change the "BibTeX" dropdown to "Biber"). Actually, to minimize friction, maybe natbib is better. Let me think about what's best for the user...

The user wants to "quickly render with a webpage service". The least friction approach: pdfLaTeX + natbib + bibtex works out of the box on Overleaf with zero configuration. Let me go with that. Actually, biblatex is nicer for author-year citations with proper formatting. But natbib with a good style like `apalike` or `plainnat` works fine too.

Hmm, let me use `biblatex` with `style=authoryear` and `biber` — it's the modern approach and Overleaf supports it with one dropdown change. I'll document it clearly. Actually, you know what, let me reconsider once more.

The user said "quickly render with a webpage service". There are also services like:
- Overleaf
- LaTeX.Online
- Papeeria
- ShareLaTeX (now Overleaf)

For maximum compatibility with minimal setup, I'll go with `natbib` + `bibtex` + `plainnat` style. This works out of the box on Overleaf with pdfLaTeX. No compiler changes needed. This is the most frictionless.

Wait, but actually there's a subtlety: with natbib, I need to use `\citep` and `\citet` commands. That's fine.

Let me design the document:

```latex
\documentclass[11pt,a4paper]{article}

% Packages
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{geometry}
\usepackage{enumitem}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{titlesec}
\usepackage{parskip} % or setspace
\usepackage{natbib}
\usepackage{url}
...
```

Structure:
1. Title block (custom, not \maketitle necessarily, or use \maketitle with custom titlepage)
2. Project Summary (Abstract)
3. Background
4. Project Goals
5. Functional Requirements
   - 1. Core Tooling for VITs
   - 2. Collaborative Workspaces
   - 3. Delta Model & Versioning
   - 4. Analytics & Interaction Telemetry
   - 5. Insights & Content Analysis
6. Non-Functional Requirements
7. Deliverables
8. Future Work
9. References

I'll create:
- `docs/latex/project_proposal.tex` (main file)
- `docs/latex/references.bib` (bibliography)
- `docs/latex/README.md` (instructions for Overleaf)

Actually, maybe I should put it in a dedicated folder like `docs/latex/` or `report/`. Let me use `docs/latex/`.

Let me also think about whether to use `\citep`/`\citet` inline citations in the text. The markdown has inline citations like "(Aaen, 2008; Aaen, 2012)". I should convert these to proper LaTeX citations using `\citep{aaen2008essence, aaen2012essence}` etc. This makes the document much more professional and the bibliography properly formatted.

Let me map the citations:
- "Building on the *Essence* approach to software innovation (Aaen, 2008; Aaen, 2012)" → `\citep{aaen2008, aaen2012}`
- "Business Model Canvas (Osterwalder & Pigneur, 2010)" → `\citep{osterwalder2010}`
- "Lean Canvas (Maurya, 2012)" → `\citep{maurya2012}`
- "Design Principle Canvas (Schoormann et al., 2023)" → `\citep{schoormann2023}`
- "digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)" → `\citep{roschnik2024, avdiji2020}`
- "collaborative visual analytics (Chen et al., 2020; Chen et al., 2021; Kolloffel et al., 2011; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, kolloffel2011, hu2021}`
- "visual inquiry for sharing contextual knowledge (Sandberg, 2011)" → `\citep{sandberg2011}`
- "Presence, awareness, and representational guidance follow findings ... (Kolloffel et al., 2011; Chen et al., 2020; Chen et al., 2021)" → `\citep{kolloffel2011, chen2020, chen2021}`
- "Event models and visual representations ... (Chen et al., 2020; Chen et al., 2021; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, hu2021}`
- "Content-level coherence builds on design theory ... (Avdiji et al., 2020) and canvas-based guidance ... (Schoormann et al., 2023)" → `\citep{avdiji2020, schoormann2023}`

For the "Examples of existing tools in literature" list, I can keep them as a list with citations.

For frameworks and libraries, I'll add them as @misc or @online entries:
- Elixir: @online
- Phoenix: @online
- Delta CRDTs: @online (GitHub repo)
- LiveView: @online

Now, for the BibTeX entries, let me write them carefully:

```bibtex
@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  volume  = {17},
  number  = {5},
  pages   = {543--551},
  doi     = {10.1057/ejis.2008.43}
}
```

Hmm, I don't know the exact volume/pages. Let me not fabricate details. I'll include what's known: author, title, year, journal, doi. For the DOI, I can use the `doi` field which natbib/plainnat will render as a URL if hyperref is loaded. Actually plainnat doesn't render doi field by default. Let me use `url` field with the doi link instead, or use `\usepackage{doi}`. Hmm.

Actually, with natbib + plainnat, the `doi` field is not printed. To keep it simple and correct, I'll put the DOI in the `url` field or use the `doi` package. Let me use the `doi` package which converts doi fields to clickable links. That's clean.

Actually, let me reconsider: `\usepackage{doi}` works with natbib and prints DOIs as links. Good.

For Aaen 2012 "Essence: Team-Based Software Innovation" — this appears to be a book or report. I'll make it @book or @misc. The markdown doesn't give a publisher. I'll use @misc with note or just @book without publisher. Let me use @misc to be safe... Actually, since it's cited as a book-like work, @book is fine but I don't have publisher info. Let me use @misc with a note. Hmm, actually for the report, I'll keep it simple: @book with just author/title/year, and note "Publisher information not specified in source document" — no, that's ugly. Let me just use @misc.

Actually, let me think about what's cleanest. I'll use:

```bibtex
@misc{aaen2012essence,
  author = {Aaen, Ivan},
  title  = {Essence: Team-Based Software Innovation},
  year   = {2012}
}
```

For books:
```bibtex
@book{osterwalder2010business,
  author    = {Osterwalder, Alexander and Pigneur, Yves},
  title     = {Business Model Generation},
  year      = {2010},
  publisher = {Wiley},
  url       = {https://www.strategyzer.com/books/business-model-generation}
}

@book{maurya2012running,
  author    = {Maurya, Ash},
  title     = {Running Lean},
  year      = {2012},
  publisher = {O'Reilly Media},
  url       = {https://leanspark.ai/leancanvas}
}
```

For conference papers:
```bibtex
@inproceedings{sandberg2011visual,
  author    = {Sandberg, F},
  title     = {Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge},
  booktitle = {Nordic Design Research Conference},
  year      = {2011},
  doi       = {10.21606/nordes.2011.028}
}

@article{schoormann2023guiding,
  author  = {Schoormann, Thorsten and M{\"o}ller, Frederik and Di Maria, Marco and Gro{\ss}e, N},
  title   = {Guiding Design Principle Projects: A Canvas for Young Design Science Researchers},
  journal = {Journal of Information Systems Education},
  year    = {2023},
  doi     = {10.62273/wkbc7575}
}

@inproceedings{roschnik2024approaching,
  author    = {Roschnik, A and Jaccard, D and Monnier, S and Missonier, S},
  title     = {Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform},
  booktitle = {ICIS Proceedings},
  year      = {2024}
}

@article{avdiji2020design,
  author  = {Avdiji, Hazbi and Elikan, Dina and Missonier, St{\'e}phanie and Pigneur, Yves},
  title   = {A Design Theory for Visual Inquiry Tools},
  journal = {Journal of the Association for Information Systems},
  year    = {2020},
  volume  = {21},
  number  = {6},
  doi     = {10.17705/1jais.00617}
}
```

Hmm, I need to be careful not to fabricate volume/number info. For Avdiji 2020, the DOI is 10.17705/1jais.00617. I know the JAIS article... I shouldn't fabricate. Let me include only what's in the source: author, title, journal, year, doi. That's safe.

For the collaboration papers:
```bibtex
@article{kolloffel2011comparing,
  author  = {Kolloffel, Bas and Eysink, Tessa H. S. and de Jong, Ton},
  title   = {Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning},
  journal = {International Journal of Computer-Supported Collaborative Learning},
  year    = {2011},
  volume  = {6},
  number  = {2},
  pages   = {223--251},
  doi     = {10.1007/s11412-011-9110-3}
}
```

Hmm, again, I know this paper has volume 6, pages 223-251, but I shouldn't fabricate. Let me just include author, title, journal, year, doi. Actually, the DOI is given in the source, so I'll include that. Volume/pages I'll omit to avoid fabrication.

```bibtex
@article{chen2020collaborative,
  author  = {Chen, Lin and Liang, Hai-Ning and Lu, Feiyu and Papangelis, Konstantinos and Man, Ka Lok and Yue, Yong},
  title   = {Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices},
  journal = {Human-centric Computing and Information Sciences},
  year    = {2020},
  volume  = {10},
  doi     = {10.1186/s13673-020-00253-7}
}
```

Hmm, volume 10 is correct for this one (it's article 40 in volume 10). But again, to be safe, I'll omit volume. Actually, the DOI is enough.

```bibtex
@article{chen2021large,
  author  = {Chen, Lin and Liang, Hai-Ning and Wang, Junxiu and Qu, Yuxuan and Yue, Yong},
  title   = {On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks},
  journal = {Sensors},
  year    = {2021},
  volume  = {21},
  number  = {24},
  doi     = {10.3390/s21248403}
}
```

Again, I'll omit volume/number to be safe. Just author, title, journal, year, doi.

```bibtex
@article{hu2021systematic,
  author  = {Hu, L and Chen, G},
  title   = {A Systematic Review of Visual Representations for Analyzing Collaborative Discourse},
  journal = {Educational Research Review},
  year    = {2021},
  doi     = {10.1016/j.edurev.2021.100403}
}
```

For frameworks:
```bibtex
@online{elixir,
  author = {Elixir Team},
  title  = {Elixir},
  year   = {2026},
  url    = {https://elixir-lang.org}
}

@online{phoenix,
  author = {Phoenix Framework},
  title  = {Phoenix},
  year   = {2026},
  url    = {https://www.phoenixframework.org}
}

@online{delta_crdt,
  author = {Kraan, Derek},
  title  = {Delta CRDTs},
  year   = {2026},
  url    = {https://github.com/derekkraan/delta_crdt_ex}
}

@online{liveview,
  author = {Phoenix Framework},
  title  = {Phoenix LiveView},
  year   = {2026},
  url    = {https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView}
}
```

Note: `@online` requires natbib to handle it. plainnat handles @online? Actually, plainnat is a bibtex style, and @online entries are supported by newer bibtex styles. plainnat does support @online I believe (it's in the natbib distribution). Yes, plainnat supports @online.

Hmm wait, actually there might be an issue: plainnat.bst handles @online? Let me think. plainnat.bst is from the natbib package and it does handle @online and @electronic. Yes, it does.

Now for the LaTeX document itself. Let me write a clean, professional document:

```latex
\documentclass[11pt,a4paper]{article}

% ---- Packages ----
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{geometry}
\geometry{margin=2.5cm}
\usepackage{graphicx}
\usepackage{xcolor}
\usepackage{booktabs}
\usepackage{enumitem}
\usepackage{parskip}
\usepackage{microtype}
\usepackage{doi}
\usepackage[round]{natbib}
\usepackage[hidelinks]{hyperref}
\usepackage{titlesec}
```

Wait, `\usepackage{doi}` — the doi package. It works with natbib. Good.

For the title, I'll create a custom title block:

```latex
\begin{titlepage}
  \centering
  \vspace*{2cm}
  {\Huge\bfseries Developing a Configurable Platform for Collaborative Visual Inquiry Tools\par}
  \vspace{0.5cm}
  {\LARGE The Problem--Solution Canvas\par}
  \vspace{2cm}
  {\large 9th Semester Project Proposal\par}
  \vspace{1cm}
  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
    \textbf{Student:} & Beltran Aceves \\
  \end{tabular}
  \vfill
  {\large \today\par}
\end{titlepage}
```

Hmm, but the user might want to keep the emails. Let me include them with \href.

Actually, let me reconsider the structure. The original has:
- Title
- 9th Semester
- Supervisor/Student with emails
- Project Summary
- Background
- Project Goals
- Functional Requirements (1-5)
- Non-Functional Requirements
- Deliverables
- Future Work
- References

I'll structure it as:
- Title page
- Abstract (Project Summary)
- Background
- Project Goals
- Functional Requirements
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the "Examples of existing tools" lists, I'll use itemize environments.

For the industry tools with URLs, I'll use \href.

Let me also think about the "quickly render with a webpage service" part. The user wants to render this quickly. Options:
1. Overleaf — upload the .tex and .bib files, compile with pdfLaTeX + BibTeX
2. A local service

I'll create a README with instructions for Overleaf, including:
- Create a new project, upload files
- Compile with pdfLaTeX (default) and BibTeX
- The natbib approach needs no special compiler settings

Let me also consider: should I use `biblatex` instead? With biblatex, the user needs to switch the compiler to biber in Overleaf. That's one extra step. natbib + bibtex works out of the box. I'll go with natbib.

Actually, wait. Let me reconsider. Modern Overleaf projects default to pdfLaTeX with "BibTeX" as the bibliography tool. natbib + plainnat + bibtex works perfectly with zero configuration. 

Let me now also think about whether to include a `\tableofcontents`. For a proposal document, a TOC is nice. I'll include it.

Let me write the full LaTeX document now.

One more consideration: the em-dash in "Problem–Solution Canvas" — I'll use `Problem--Solution` in LaTeX.

Also "9th Semester" — I'll put it on the title page.

Let me draft the full .tex file:

```latex
% ============================================================================
%  Project Proposal: A Configurable Platform for Collaborative Visual
%  Inquiry Tools — The Problem–Solution Canvas
%
%  Compile with pdfLaTeX + BibTeX (works out of the box on Overleaf).
% ============================================================================
\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts -------------------------------------------------------
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{microtype}

% --- Page layout ------------------------------------------------------------
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt, itemsep=2pt, parsep=0pt}

% --- Graphics & colors ------------------------------------------------------
\usepackage{xcolor}
\usepackage{graphicx}

% --- Tables -----------------------------------------------------------------
\usepackage{booktabs}

% --- Hyperlinks & DOIs ------------------------------------------------------
\usepackage[hidelinks]{hyperref}
\urlstyle{same}
\usepackage{doi}

% --- Citations --------------------------------------------------------------
\usepackage[round]{natbib}
\bibliographystyle{plainnat}

% --- Section formatting -----------------------------------------------------
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}

% --- Metadata ---------------------------------------------------------------
\title{Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem--Solution Canvas}
\author{Beltran Aceves}
\date{9th Semester}

\begin{document}

% --- Title page -------------------------------------------------------------
\begin{titlepage}
  \centering
  \vspace*{1.5cm}

  {\Huge\bfseries Developing a Configurable Platform for\\[0.3em] Collaborative Visual Inquiry Tools\par}
  \vspace{0.6cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{2.5cm}

  {\large 9th Semester Project Proposal\par}

  \vspace{1.5cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{ivan@cs.aau.dk} \\[0.5em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{baceve25@student.aau.dk} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}

\tableofcontents
\newpage

% --- Project Summary --------------------------------------------------------
\section{Project Summary}
...
```

Wait, the emails in the original have typos: `ivan@cs.af` and `baceve25@stduent.aau.dk`. These are clearly typos in the markdown (the mailto links are `mailto:ivan@cs.af` and `mailto:baceve25@stduent.aau.dk`). The display text is `ivan@cs.aau.dk` and `baceve25@student.aau.dk`. I'll use the correct display emails: `ivan@cs.aau.dk` and `baceve25@student.aau.dk`.

Now the body content. Let me convert each section:

**Project Summary:**
```latex
\section{Project Summary}

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem--Solution Canvas (PSC), developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems.

The platform will therefore let users:
\begin{itemize}
  \item define and share canvas templates (e.g., PSC variants);
  \item instantiate collaborative canvas instances that load and synchronize in real time;
  \item explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, and supports visualizing and traversing versions;
  \item automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event stream datasets;
  \item analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.
\end{itemize}

Implemented as a web application using the Elixir/Phoenix/Postgres stack, the platform will provide CRDT-based real-time collaboration, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.
```

**Background:**
```latex
\section{Background}

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem--Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the \emph{Essence} approach to software innovation \citep{aaen2008essence,aaen2012essence}, the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as Strategyzer \citep{...}...
```

Hmm, for the industry platforms, they're websites, not citations. I'll use \href for them.

```latex
Existing industry platforms such as \href{https://www.strategyzer.com}{Strategyzer}, \href{https://miro.com}{Miro}, \href{https://www.mural.co}{MURAL}, \href{https://canvanizer.com}{Canvanizer}, \href{https://leanspark.ai/leancanvas}{Lean Canvas}, and \href{https://designthinking.ideo.com/}{IDEO Design Thinking Tools} provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time or whether canvas content remains coherent and up to date. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas \citep{osterwalder2010business}, Lean Canvas \citep{maurya2012running}, Design Principle Canvas \citep{schoormann2023guiding}, and recent work on digital inquiry platforms \citep{roschnik2024approaching,avdiji2020design} and collaborative visual analytics \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}, as well as visual inquiry for sharing contextual knowledge \citep{sandberg2011visual}. This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, fine-grained interaction tracing, and content-level insights into a unified research-oriented platform.
```

Then the two lists:

```latex
\subsection{Examples of Existing Tools in Literature}
\begin{itemize}
  \item \textbf{Business Model Canvas} --- Osterwalder, A., \& Pigneur, Y. (2010). \emph{Business Model Generation}. \citep{osterwalder2010business}
  \item \textbf{Lean Canvas} --- Maurya, A. (2012). \emph{Running Lean}. \citep{maurya2012running}
  \item \textbf{Design Principle Canvas} --- Schoormann, T., et al. (2023). \emph{Guiding Design Principle Projects: A Canvas for Young Design Science Researchers}. \citep{schoormann2023guiding}
  \item \textbf{Digital Inquiry Platform concepts} --- Roschnik, A., et al. (2024). \emph{Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform}. See also Avdiji et al. (2020). \citep{roschnik2024approaching,avdiji2020design}
  \item \textbf{Collaborative visual inquiry and analytics research} --- Chen, L., et al. (2020). \emph{Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices}. See also Chen et al. (2021); Kolloffel et al. (2011); Hu \& Chen (2021). \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}
  \item \textbf{Visual inquiry and contextual knowledge sharing} --- Sandberg, F. (2011). \emph{Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge}. \citep{sandberg2011visual}
\end{itemize}

\subsection{Examples of Existing Tools in Industry}
\begin{itemize}
  \item \href{https://www.strategyzer.com/library?type=Tools}{Strategyzer}
  \item \href{https://miro.com}{Miro}
  \item \href{https://www.mural.co/templates}{MURAL}
  \item \href{https://canvanizer.com}{Canvanizer}
  \item \href{https://leanspark.ai/leancanvas}{Lean Canvas}
  \item \href{https://designthinking.ideo.com/}{Design Thinking tools (IDEO U)}
\end{itemize}
```

**Project Goals:**
```latex
\section{Project Goals}

The project focuses on building the MVP:
\begin{itemize}
  \item Development of the main web application with VIT core features;
  \item Implementation of the delta-based versioning system: explicit milestones/versions/commits in a traversable tree, with visualization and recorded pivot/bifurcation rationale;
  \item Implementation of the insights system for analyzing canvas content (coherence, staleness, quality signals, with optional LLM-enabled insights);
  \item Implementation of the analytics engine (automatic capture of interaction events and metrics) to lay the foundation for later study.
\end{itemize}
```

**Functional Requirements:**
```latex
\section{Functional Requirements}

\subsection{Core Tooling for VITs}
Design and implement core tooling for building Visual Inquiry Tools (VITs). This includes:
\begin{itemize}
  \item defining canvas structure (cells, relations, semantics) and templates;
  \item editor UI and components for creating and editing cells;
  \item template persistence and instantiation of canvases.
\end{itemize}

\subsection{Collaborative Workspaces}
Develop workspaces for real-time collaboration on canvases. This includes:
\begin{itemize}
  \item real-time collaborative editing using CRDTs with live document loading and conflict-free merges;
  \item per-user presence and cursor indicators, plus inline comments and discussion threads;
  \item sharing, access control, and session management for team sessions.
\end{itemize}

Presence, awareness, and representational guidance follow findings on collaborative inquiry learning and engagement with shared visual tasks \citep{kolloffel2011comparing,chen2020collaborative,chen2021large}.

\subsection{Delta Model \& Versioning}
A PSC, or any other VIT instance, evolves continuously during collaborative real-time sessions. This fluid evolution is normal and expected, but teams also need to explicitly mark that they have reached a meaningful point in the progress of their project or canvas.

The delta system provides this intentional versioning layer, to:
\begin{itemize}
  \item let users create explicit milestones/versions/commits (snapshots) of the canvas at chosen moments;
  \item organize versions in a tree-like manner supporting linear history as well as branches for pivots, bifurcations, and parallel alternatives;
  \item visualize and traverse the version tree (timeline/tree view, diff/compare between versions, restore or fork from any version);
  \item record the reason for each pivot or bifurcation (decision rationale, reinterpretation note, author, timestamp, parent link(s));
  \item provide tools to annotate and group deltas/versions for later analysis.
\end{itemize}

\subsection{Analytics \& Interaction Telemetry}
The platform provides an analytics engine that automatically captures all kinds of events and metrics from users interacting with the system, so they can be analyzed later:
\begin{itemize}
  \item passively log interaction events (edits, navigation, presence, comments, version operations, insight views) with order, frequency/distribution, and metadata (who, when, where in the canvas, session/device context);
  \item expose exportable event streams and lightweight aggregation APIs for research use;
  \item enable studies of user archetypes, framing patterns, collaboration dynamics, and outcome correlations.
\end{itemize}

Event models and visual representations for collaborative discourse build on prior work in visual analytics and discourse analysis \citep{chen2020collaborative,chen2021large,hu2021systematic}.

\subsection{Insights \& Content Analysis}
Analyze the contents of a given PSC to support reflection and convergence, complementing the interaction-level analytics in Section~\ref{sec:analytics}:
\begin{itemize}
  \item detect cells deviating from the central theme or problem framing of the canvas;
  \item detect old/stale cells (e.g., untouched, superseded, or inconsistent with recent pivots/decisions);
  \item surface coherence and quality signals (e.g., contradictions, gaps, duplicates across cells);
  \item provide LLM-enabled insights where appropriate (e.g., summaries, suggestions, theme-drift explanations), designed as an optional, pluggable layer over deterministic heuristics so the platform remains usable without an LLM provider.
\end{itemize}

Content-level coherence builds on design theory for visual inquiry tools \citep{avdiji2020design} and canvas-based guidance for design projects \citep{schoormann2023guiding}.
```

I need to add a label to the analytics section: `\label{sec:analytics}`.

**Non-Functional Requirements:**
```latex
\section{Non-Functional Requirements}
\begin{itemize}
  \item The platform should be built using the Elixir/Phoenix stack for scalability and real-time capabilities.
  \item The system should be designed for extensibility to support future features and different types of VIT, including new insight detectors and LLM providers.
  \item The user interface should be intuitive and responsive to facilitate collaboration and ease of use, including support for both desktop and mobile devices.
  \item The platform should ensure data integrity and consistency during real-time collaboration, using CRDTs for conflict-free merging of changes.
  \item The analytics infrastructure should be designed to efficiently capture and store interaction data while minimizing performance overhead on the user experience.
  \item The insights system should run efficiently alongside editing (e.g., asynchronous/on-demand analysis) and keep LLM usage optional, privacy-aware, and clearly attributed, so canvases remain fully usable without external AI services.
  \item The system should be easy to deploy and maintain, with clear documentation for both users and developers.
\end{itemize}
```

**Deliverables:**
```latex
\section{Deliverables}
\begin{itemize}
  \item A working web application built with Elixir/Phoenix;
  \item Project documentation and deployment guide;
  \item Support for:
  \begin{itemize}
    \item configurable visual inquiry templates;
    \item collaborative canvas instances;
    \item delta-based pivot versioning;
    \item insights system for canvas content analysis (theme deviation, stale cells, coherence signals, with optional LLM-enabled insights);
    \item a basic analytics engine automatically capturing user interaction events and metrics, with exportable streams for later analysis;
  \end{itemize}
  \item A written report describing:
  \begin{itemize}
    \item design decisions;
    \item system architecture;
    \item and implications for supporting visual inquiry and innovation.
  \end{itemize}
\end{itemize}
```

**Future Work:**
```latex
\section{Future Work}

The following are out of scope for the MVP but are natural next steps once the core platform is in place.

\paragraph{Experiments on user behavior.}
Design and run studies using the analytics engine to look at patterns of use, problem framing, and solution development; such as user archetypes, framing patterns, collaboration dynamics, and how they relate to outcomes. This would also mean scaling up the analytics side: experiment tooling, aggregation APIs, and dataset exports for larger studies.

\paragraph{Non-table canvases.}
The MVP assumes table-like canvases made of cells. Later we want templates that are not grids at all: a background image or SVG with floating text inputs placed on top of it. This would support more visual or spatial VITs (maps, diagrams, annotated pictures) using the same collaboration, versioning, and analytics foundations.
```

**References:**
```latex
\section{References}
\bibliography{references}
```

Wait, I should organize the references. The original has subsections: Frameworks and Libraries, Core Concepts, Visual Inquiry Tools and Collaborative Inquiry, Collaboration Visual Analytics and Interaction Analysis. With a single .bib file and plainnat, the references will be alphabetical. That's fine and standard. I could add \nocite for all entries. Since I cite everything in the text, all entries will appear. Let me double check: do I cite all entries?

- aaen2008essence ✓ (Background)
- aaen2012essence ✓ (Background)
- osterwalder2010business ✓ (Background + literature list)
- maurya2012running ✓ (Background + literature list)
- schoormann2023guiding ✓ (Background + literature list + insights)
- roschnik2024approaching ✓ (Background + literature list)
- avdiji2020design ✓ (Background + literature list + insights)
- chen2020collaborative ✓ (Background + literature list + workspaces + analytics)
- chen2021large ✓ (Background + literature list + workspaces + analytics)
- kolloffel2011comparing ✓ (Background + literature list + workspaces)
- hu2021systematic ✓ (Background + literature list + analytics)
- sandberg2011visual ✓ (Background + literature list)
- elixir ✓ (need to cite in text)
- phoenix ✓ (need to cite in text)
- delta_crdt ✓ (need to cite in text)
- liveview ✓ (need to cite in text)

For the frameworks, I should cite them in the text. In the Project Summary: "Implemented as a web application using the Elixir/Phoenix/Postgres stack" — I can add citations there: `\citep{elixir,phoenix}`. And for CRDT-based real-time collaboration: `\citep{delta_crdt}`. And LiveView: maybe in the summary or background. Let me add them naturally:

"Implemented as a web application using the Elixir/Phoenix/Postgres stack \citep{elixir,phoenix}, the platform will provide CRDT-based real-time collaboration \citep{delta_crdt}, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents."

And LiveView: "using the Elixir/Phoenix stack \citep{elixir,phoenix,liveview}" — hmm, LiveView is part of Phoenix. Let me cite it in the summary too or in the workspaces section. Actually, let me cite it in the summary: `\citep{elixir,phoenix,liveview}`. That works.

Now, the .bib file. Let me write it carefully with proper LaTeX escaping (e.g., `{\"o}` or `{\"o}` for ö, `\&` for &).

For Schoormann: Möller → M{\"o}ller, Große → Gro{\ss}e. Actually "Große" — the markdown says "Große, N." Let me write Gro{\ss}e.

For Avdiji: Stéphanie → St{\'e}phanie.

Now, one issue: `\usepackage{doi}` — the doi package. It works with natbib and converts doi fields to clickable links. Good.

Also, I should think about whether `plainnat` handles `@online`. Yes, plainnat.bst supports @online entries (it treats them like @misc with url). Good.

Let me also add `\usepackage{url}` — actually hyperref loads url internally. `\urlstyle{same}` makes URLs use the same font. Good.

Now, about the README for Overleaf. Let me write clear instructions:

```markdown
# LaTeX version of the Project Proposal

This folder contains a LaTeX version of `docs/project_proposal.md`, ready to compile on Overleaf (or any LaTeX distribution).

## Files
- `project_proposal.tex` — main document
- `references.bib` — BibTeX bibliography

## Quick start on Overleaf
1. Go to https://www.overleaf.com and create a new project (Blank Project).
2. Upload `project_proposal.tex` and `references.bib` (or copy-paste the contents).
3. Make sure the compiler is set to **pdfLaTeX** (default) and the bibliography tool is **BibTeX** (default).
4. Click **Recompile**. The bibliography is generated automatically.

## Local compilation
```bash
pdflatex project_proposal
bibtex project_proposal
pdflatex project_proposal
pdflatex project_proposal
```

## Notes
- Citations use `natbib` with the `plainnat` style (author–year).
- DOIs are rendered as clickable links via the `doi` package.
- All references from the markdown are included in `references.bib`.
```

Now, where to put these files? I'll create `docs/latex/` folder with:
- `project_proposal.tex`
- `references.bib`
- `README.md`

Let me also double-check the LaTeX for any issues:

1. `\citep{...}` with multiple keys — fine.
2. The `doi` package — `\usepackage{doi}`. Fine.
3. `\href{mailto:...}` — fine with hyperref.
4. `\paragraph` — fine.
5. `\tableofcontents` — fine.
6. Title page — fine.

One thing: `\usepackage[round]{natbib}` gives (Author, Year) style citations. Good for a proposal.

Also, I should consider adding `\setlength{\parskip}` via parskip package — done.

Let me also think about the em-dash usage. In the title: "The Problem–Solution Canvas" uses an en-dash. In LaTeX: `Problem--Solution`.

Also "9th Semester" — I'll put it on the title page and in the date.

Let me also handle the "Project Summary" — should it be an abstract? I'll keep it as a section titled "Project Summary" to match the original. Actually, I could use `\begin{abstract}` but the original calls it "Project Summary". Let me keep it as a section for fidelity.

Hmm, one more thought: should I use `report` class instead of `article`? The document has sections (not chapters), so `article` is appropriate.

Let me also add a nice touch: `\usepackage{setspace}` with `\onehalfspacing`? That's common for reports. Hmm, it might make it longer. Let me keep single spacing but with parskip. Actually, for a proposal document, onehalfspacing is common in academic settings. But to keep it simple and compact, I'll skip it. Actually, let me add it as an option — no, keep it simple.

Let me also think about fonts. Default Computer Modern is fine. I could use `\usepackage{lmodern}` for better rendering. Let me add lmodern.

Now let me also double check: the user said "quickly render with a webpage service". Maybe they also want to know about services that render LaTeX in the browser without an account. There are services like:
- Overleaf (needs account, free)
- LaTeX.Online (renders in browser)
- Papeeria
- TeXLive.net (renders LaTeX snippets via URL)

I'll mention Overleaf primarily in the README, and maybe briefly mention alternatives.

Let me now create the files. I'll create:
1. `docs/latex/project_proposal.tex`
2. `docs/latex/references.bib`
3. `docs/latex/README.md`

Let me write the complete .tex file content:

Actually, let me reconsider the title page. The original title is "Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem–Solution Canvas". I'll split it across lines nicely.

Let me also add a footer with page numbers — default article class has page numbers. Good.

Let me write everything now. I'll be careful with special characters:
- `&` → `\&`
- `%` → `\%` (none in text I think)
- `#` → `\#` (none)
- `_` → `\_` (none in text)
- `~` → `\textasciitilde` (none)
- `$` → `\$` (none)

In the bib file:
- `&` → `\&` (e.g., "Osterwalder, A., & Pigneur, Y." → in bib, author field uses "and" so no & needed)
- `ö` → `{\"o}`
- `é` → `{\'e}`
- `ß` → `{\ss}`

Let me write the bib entries:

```bibtex
% ============================================================================
%  References for the Project Proposal
%  Compiled with BibTeX using the plainnat style (natbib).
% ============================================================================

% --- Frameworks and Libraries ------------------------------------------------

@online{elixir,
  author = {{Elixir Team}},
  title  = {Elixir},
  year   = {2026},
  url    = {https://elixir-lang.org}
}

@online{phoenix,
  author = {{Phoenix Framework}},
  title  = {Phoenix},
  year   = {2026},
  url    = {https://www.phoenixframework.org}
}

@online{delta_crdt,
  author = {Kraan, Derek},
  title  = {Delta CRDTs},
  year   = {2026},
  url    = {https://github.com/derekkraan/delta_crdt_ex}
}

@online{liveview,
  author = {{Phoenix Framework}},
  title  = {Phoenix LiveView},
  year   = {2026},
  url    = {https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView}
}

% --- Core Concepts -----------------------------------------------------------

@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  doi     = {10.1057/ejis.2008.43}
}

@misc{aaen2012essence,
  author = {Aaen, Ivan},
  title  = {Essence: Team-Based Software Innovation},
  year   = {2012}
}

@book{osterwalder2010business,
  author    = {Osterwalder, Alexander and Pigneur, Yves},
  title     = {Business Model Generation},
  year      = {2010},
  publisher = {Wiley},
  url       = {https://www.strategyzer.com/books/business-model-generation}
}

@book{maurya2012running,
  author    = {Maurya, Ash},
  title     = {Running Lean},
  year      = {2012},
  publisher = {O'Reilly Media},
  url       = {https://leanspark.ai/leancanvas}
}

% --- Visual Inquiry Tools and Collaborative Inquiry --------------------------

@inproceedings{sandberg2011visual,
  author    = {Sandberg, F},
  title     = {Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge},
  booktitle = {Nordic Design Research Conference},
  year      = {2011},
  doi       = {10.21606/nordes.2011.028}
}

@article{schoormann2023guiding,
  author  = {Schoormann, Thorsten and M{\"o}ller, Frederik and Di Maria, Marco and Gro{\ss}e, N},
  title   = {Guiding Design Principle Projects: A Canvas for Young Design Science Researchers},
  journal = {Journal of Information Systems Education},
  year    = {2023},
  doi     = {10.62273/wkbc7575}
}

@inproceedings{roschnik2024approaching,
  author    = {Roschnik, A and Jaccard, D and Monnier, S and Missonier, S},
  title     = {Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform},
  booktitle = {ICIS Proceedings},
  year      = {2024}
}

@article{avdiji2020design,
  author  = {Avdiji, Hazbi and Elikan, Dina and Missonier, St{\'e}phanie and Pigneur, Yves},
  title   = {A Design Theory for Visual Inquiry Tools},
  journal = {Journal of the Association for Information Systems},
  year    = {2020},
  doi     = {10.17705/1jais.00617}
}

% --- Collaboration, Visual Analytics, and Interaction Analysis ---------------

@article{kolloffel2011comparing,
  author  = {Kolloffel, Bas and Eysink, Tessa H. S. and de Jong, Ton},
  title   = {Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning},
  journal = {International Journal of Computer-Supported Collaborative Learning},
  year    = {2011},
  doi     = {10.1007/s11412-011-9110-3}
}

@article{chen2020collaborative,
  author  = {Chen, Lin and Liang, Hai-Ning and Lu, Feiyu and Papangelis, Konstantinos and Man, Ka Lok and Yue, Yong},
  title   = {Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices},
  journal = {Human-centric Computing and Information Sciences},
  year    = {2020},
  doi     = {10.1186/s13673-020-00253-7}
}

@article{chen2021large,
  author  = {Chen, Lin and Liang, Hai-Ning and Wang, Junxiu and Qu, Yuxuan and Yue, Yong},
  title   = {On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks},
  journal = {Sensors},
  year    = {2021},
  doi     = {10.3390/s21248403}
}

@article{hu2021systematic,
  author  = {Hu, L and Chen, G},
  title   = {A Systematic Review of Visual Representations for Analyzing Collaborative Discourse},
  journal = {Educational Research Review},
  year    = {2021},
  doi     = {10.1016/j.edurev.2021.100403}
}
```

Wait, for `@online` with `author = {{Elixir Team}}` — the double braces prevent BibTeX from interpreting "Elixir Team" as "Team, Elixir". Good.

Hmm, one concern: `plainnat.bst` and `@online` — plainnat does support @online. Let me double check... plainnat.bst from natbib distribution: it handles @article, @book, @booklet, @inbook, @incollection, @inproceedings, @conference, @manual, @mastersthesis, @misc, @phdthesis, @proceedings, @techreport, @unpublished, @online, @electronic, @www. Yes, plainnat supports @online. 

Now, one more consideration: the `doi` package. When using natbib with plainnat, the doi package hooks into the bibliography to print DOIs. It works. But there's a subtlety: the doi package requires the `url` package (loaded by hyperref). Fine.

Actually, let me reconsider whether to use the `doi` package or just put DOIs in `url` fields. The `doi` package is simpler and cleaner. Let me keep it.

Now, let me also think about whether the user might want to compile this locally too. The README covers both.

Let me also consider adding a `\section*{Abstract}` vs keeping "Project Summary". I'll keep "Project Summary" as the section title to match the original document.

One more thing: the original has "9th Semester" right after the title. I'll include it on the title page.

Let me also think about the date. The current date is 2026-09-17. I'll use `\today` which will render the compile date. That's fine.

Now let me create the files. Let me also verify the folder structure — I'll create `docs/latex/`.

Actually, wait — should I ask the user any clarifying questions? The request is fairly clear: transform the markdown into a LaTeX/Overleaf document. I could ask about:
- Whether they want a specific document class (article vs report)
- Whether they want the full bibliography as BibTeX
- Whether they want it in a specific folder

But these are minor decisions I can make sensibly. The user said "quickly render with a webpage service" which strongly implies Overleaf. I'll make reasonable choices and document them. I don't think I need to ask questions — the task is clear enough. Let me just do it well.

Let me create the three files now.

Actually, let me reconsider one thing about the title page layout. Let me make it clean:

```latex
\begin{titlepage}
  \centering
  \vspace*{2cm}

  {\Huge\bfseries Developing a Configurable Platform for Collaborative Visual Inquiry Tools\par}
  \vspace{0.8cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{3cm}

  {\large 9th Semester --- Project Proposal\par}

  \vspace{2cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{\texttt{ivan@cs.aau.dk}} \\[0.8em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{\texttt{baceve25@student.aau.dk}} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}
```

Good. Now the full document. Let me write it out completely and carefully.

Also, I want to double-check the `\citep` usage in the "Examples of Existing Tools in Literature" list. Since the list items already contain the full citation info (author, year, title), adding `\citep` would duplicate. Hmm. Let me think...

Option A: Keep the list items as descriptive text with the full citation info, and add `\citep` at the end for the bibliography entry. This creates redundancy in the list but ensures the bibliography is complete.

Option B: Make the list items reference the bibliography entries only, e.g., "Business Model Canvas — \citet{osterwalder2010business}". This is cleaner but loses the descriptive titles.

Since all these works are already cited in the Background section text, the bibliography will be complete even without citing them in the lists. So in the lists, I can keep the descriptive text as-is (matching the original markdown) without adding \citep. That avoids redundancy. The Background paragraph already cites all of them.

Wait, let me verify: does the Background paragraph cite ALL of them?
- osterwalder2010business ✓ ("Business Model Canvas (Osterwalder & Pigneur, 2010)")
- maurya2012running ✓ ("Lean Canvas (Maurya, 2012)")
- schoormann2023guiding ✓ ("Design Principle Canvas (Schoormann et al., 2023)")
- roschnik2024approaching ✓ ("digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)")
- avdiji2020design ✓ (same)
- chen2020collaborative ✓ ("collaborative visual analytics (Chen et al., 2020; ...)")
- chen2021large ✓
- kolloffel2011comparing ✓
- hu2021systematic ✓
- sandberg2011visual ✓ ("visual inquiry for sharing contextual knowledge (Sandberg, 2011)")

Yes, all are cited in the Background. So the lists can be descriptive without \citep. 

But wait — there's a subtlety with natbib: if an entry is cited but the list also mentions it, that's fine. The bibliography will include all cited entries. Good.

Hmm, but actually, for the "Examples of Existing Tools in Literature" list, it might be nice to keep the full citation info in the list (as the original does) AND have them in the bibliography. The original markdown has the full info in the list. I'll keep the list items as in the original (with author, year, title) but formatted nicely. Since they're already cited in the text, the bibliography will have them. No \citep needed in the list. 

Now, let me also make sure I handle the "See also" references in the list items. E.g., "See also Avdiji et al. (2020)." I'll keep those as text.

OK let me also think about whether to add `\label` for cross-references. In the Insights section, it references "section 4" (Analytics & Interaction Telemetry). I'll add `\label{sec:analytics}` to the analytics section and reference it as `Section~\ref{sec:analytics}`.

Now, let me write the final files.

One more consideration on packages: `\usepackage{doi}` might conflict with hyperref if loaded in wrong order. The doi package should be loaded after hyperref? Actually, the doi package documentation says to load it after natbib. Order: natbib, then doi, then hyperref? Hmm. Let me think. The doi package redefines the bibliography to add DOI links. It works with hyperref. Common order: load hyperref last (it's usually loaded last). The doi package can be loaded before or after hyperref; it uses \href internally if hyperref is loaded. To be safe: load natbib, then doi, then hyperref last. Actually, hyperref should generally be loaded last among these. Let me do:

```latex
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}
\usepackage[hidelinks]{hyperref}
```

Hmm, but the doi package documentation says: "The package should be loaded after natbib and before hyperref" — actually I recall the doi package works fine either way. Let me load doi after natbib and before hyperref. That's the documented order.

Wait, actually there's a known issue: if hyperref is loaded after doi, the doi links work. If hyperref is loaded before doi, doi still works but might warn. The recommended order is natbib → doi → hyperref. Let me use that.

Also `\urlstyle{same}` should come after hyperref (or after url package). Let me put it after hyperref.

Let me finalize the preamble:

```latex
\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts ---
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{lmodern}
\usepackage{microtype}

% --- Page layout ---
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt,itemsep=2pt,parsep=0pt}

% --- Graphics ---
\usepackage{graphicx}
\usepackage{xcolor}

% --- Tables ---
\usepackage{booktabs}

% --- Citations & bibliography ---
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}

% --- Hyperlinks ---
\usepackage[hidelinks]{hyperref}
\urlstyle{same}

% --- Section formatting ---
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}
```

Hmm, `\usepackage{graphicx}` and `booktabs` aren't strictly needed (no figures/tables), but harmless. Actually, let me drop booktabs and graphicx to keep it minimal... Actually, keeping them doesn't hurt and allows future additions. I'll keep graphicx but drop booktabs since there are no tables. Actually, let me keep both minimal — I'll keep graphicx (common) and drop booktabs. Hmm, actually let me just keep the preamble lean: drop both. No wait — the user may add figures later. Let me keep graphicx. Drop booktabs.

Actually, you know what, let me keep it simple and include only what's used plus a couple of common ones (graphicx, xcolor). Fine.

Let me now also double check `\titleformat` — titlesec with `\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}`. This is fine.

Now writing the body. Let me be careful with the em-dashes in the text: "---" for em-dash, "--" for en-dash.

In "Problem–Solution Canvas" → `Problem--Solution Canvas`.

Let me write the complete file now.

Also, I realize I should double-check: does the user want me to also keep the markdown file? Yes, I'm creating new files alongside, not modifying the markdown. Good.

Let me also think about the README content more. The user said "quickly render with a webpage service". I'll write the README to cover:
1. Overleaf quick start (main path)
2. Alternative: local compilation
3. Alternative web services briefly

Let me write it.

Now, let me create all three files. I'll use create_file for each.

Let me write out the complete .tex content:

```latex
% ============================================================================
%  Project Proposal
%  Developing a Configurable Platform for Collaborative Visual Inquiry Tools:
%  The Problem–Solution Canvas
%
%  Compile with pdfLaTeX + BibTeX (default settings on Overleaf).
%  Bibliography: references.bib (natbib / plainnat, author–year style).
% ============================================================================

\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts -------------------------------------------------------
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{lmodern}
\usepackage{microtype}

% --- Page layout ------------------------------------------------------------
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt,itemsep=2pt,parsep=0pt}

% --- Graphics & colors ------------------------------------------------------
\usepackage{graphicx}
\usepackage{xcolor}

% --- Citations & bibliography -----------------------------------------------
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}

% --- Hyperlinks -------------------------------------------------------------
\usepackage[hidelinks]{hyperref}
\urlstyle{same}

% --- Section formatting -----------------------------------------------------
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}

% ============================================================================
\begin{document}

% --- Title page -------------------------------------------------------------
\begin{titlepage}
  \centering
  \vspace*{2cm}

  {\Huge\bfseries Developing a Configurable Platform for\\[0.4em] Collaborative Visual Inquiry Tools\par}
  \vspace{0.8cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{3cm}

  {\large 9th Semester --- Project Proposal\par}

  \vspace{2cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{\texttt{ivan@cs.aau.dk}} \\[0.8em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{\texttt{baceve25@student.aau.dk}} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}

% --- Table of contents ------------------------------------------------------
\tableofcontents
\newpage

% --- Project Summary --------------------------------------------------------
\section{Project Summary}

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem--Solution Canvas (PSC), developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems.

The platform will therefore let users:
\begin{itemize}
  \item define and share canvas templates (e.g., PSC variants);
  \item instantiate collaborative canvas instances that load and synchronize in real time;
  \item explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, and supports visualizing and traversing versions;
  \item automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event stream datasets;
  \item analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.
\end{itemize}

Implemented as a web application using the Elixir/Phoenix/Postgres stack \citep{elixir,phoenix,liveview}, the platform will provide CRDT-based real-time collaboration \citep{delta_crdt}, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/docs/project_proposal.md)**

<details>
<summary>💭 Thinking — Reviewed project_proposal.md</summary>

The user wants to transform their project proposal markdown document into a LaTeX/Overleaf document that they can quickly render with a webpage service.

Let me think about the best approach:

1. Create a LaTeX document (`.tex`) that mirrors the content of the project proposal
2. Make it Overleaf-compatible (using standard packages available on Overleaf)
3. Include a proper bibliography (using BibTeX or biblatex) since there are many references
4. Make it render nicely with a webpage service

The user mentioned "quickly render with a webpage service" - this could mean:
- Overleaf (the most common LaTeX editor)
- Or a service that renders LaTeX to PDF in the browser

I should create:
1. A main `.tex` file with the document structure
2. A `.bib` file with all the references
3. Maybe a README explaining how to use it in Overleaf

Let me think about the structure:
- Title page with project title, semester, supervisor, student
- Abstract/Project Summary
- Background
- Project Goals
- Functional Requirements (5 sections)
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the bibliography, I'll use BibTeX entries for all the references. Let me create proper BibTeX entries:

1. Aaen 2008 - Essence: Facilitating Software Innovation - EJIS
2. Aaen 2012 - Essence: Team-Based Software Innovation
3. Osterwalder & Pigneur 2010 - Business Model Generation
4. Maurya 2012 - Running Lean
5. Sandberg 2011 - Visual Inquiry
6. Schoormann et al. 2023 - Guiding Design Principle Projects
7. Roschnik et al. 2024 - Approaching Visual Inquiry Tools
8. Avdiji et al. 2020 - A Design Theory for Visual Inquiry Tools
9. Kolloffel et al. 2011 - Comparing the Effects of Representational Tools
10. Chen et al. 2020 - Collaborative Behavior, Performance and Engagement
11. Chen et al. 2021 - On the Use of Large Interactive Displays
12. Hu & Chen 2021 - A Systematic Review of Visual Representations

Plus frameworks/libraries:
- Elixir
- Phoenix
- Delta CRDTs
- LiveView

For the LaTeX document, I should use:
- `article` class or maybe `report` for a more structured document
- `biblatex` with `biber` (Overleaf supports this well) or traditional `natbib`/`bibtex`
- Actually, for Overleaf compatibility, both work. `biblatex` with `biber` is modern and works well on Overleaf. But `natbib` with `bibtex` is more universally compatible. Let me use `biblatex` since Overleaf handles it well, or actually let me think...

Overleaf supports both. The safest and most common approach is `natbib` + `bibtex` since it doesn't require changing the compiler settings. But `biblatex` is more modern. Overleaf's default is pdfLaTeX with bibtex. If I use biblatex, I need biber. Overleaf supports biber but the user needs to change the setting.

Actually, let me use `biblatex` with `biber` and note in the README that they need to set the compiler to biber. Or I could use natbib to keep it simple. Hmm.

Let me go with `biblatex` + `biber` since it's the modern standard and Overleaf makes it easy (just change the "BibTeX" dropdown to "Biber"). Actually, to minimize friction, maybe natbib is better. Let me think about what's best for the user...

The user wants to "quickly render with a webpage service". The least friction approach: pdfLaTeX + natbib + bibtex works out of the box on Overleaf with zero configuration. Let me go with that. Actually, biblatex is nicer for author-year citations with proper formatting. But natbib with a good style like `apalike` or `plainnat` works fine too.

Hmm, let me use `biblatex` with `style=authoryear` and `biber` — it's the modern approach and Overleaf supports it with one dropdown change. I'll document it clearly. Actually, you know what, let me reconsider once more.

The user said "quickly render with a webpage service". There are also services like:
- Overleaf
- LaTeX.Online
- Papeeria
- ShareLaTeX (now Overleaf)

For maximum compatibility with minimal setup, I'll go with `natbib` + `bibtex` + `plainnat` style. This works out of the box on Overleaf with pdfLaTeX. No compiler changes needed. This is the most frictionless.

Wait, but actually there's a subtlety: with natbib, I need to use `\citep` and `\citet` commands. That's fine.

Let me design the document:

```latex
\documentclass[11pt,a4paper]{article}

% Packages
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{geometry}
\usepackage{enumitem}
\usepackage{booktabs}
\usepackage{xcolor}
\usepackage{titlesec}
\usepackage{parskip} % or setspace
\usepackage{natbib}
\usepackage{url}
...
```

Structure:
1. Title block (custom, not \maketitle necessarily, or use \maketitle with custom titlepage)
2. Project Summary (Abstract)
3. Background
4. Project Goals
5. Functional Requirements
   - 1. Core Tooling for VITs
   - 2. Collaborative Workspaces
   - 3. Delta Model & Versioning
   - 4. Analytics & Interaction Telemetry
   - 5. Insights & Content Analysis
6. Non-Functional Requirements
7. Deliverables
8. Future Work
9. References

I'll create:
- `docs/latex/project_proposal.tex` (main file)
- `docs/latex/references.bib` (bibliography)
- `docs/latex/README.md` (instructions for Overleaf)

Actually, maybe I should put it in a dedicated folder like `docs/latex/` or `report/`. Let me use `docs/latex/`.

Let me also think about whether to use `\citep`/`\citet` inline citations in the text. The markdown has inline citations like "(Aaen, 2008; Aaen, 2012)". I should convert these to proper LaTeX citations using `\citep{aaen2008essence, aaen2012essence}` etc. This makes the document much more professional and the bibliography properly formatted.

Let me map the citations:
- "Building on the *Essence* approach to software innovation (Aaen, 2008; Aaen, 2012)" → `\citep{aaen2008, aaen2012}`
- "Business Model Canvas (Osterwalder & Pigneur, 2010)" → `\citep{osterwalder2010}`
- "Lean Canvas (Maurya, 2012)" → `\citep{maurya2012}`
- "Design Principle Canvas (Schoormann et al., 2023)" → `\citep{schoormann2023}`
- "digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)" → `\citep{roschnik2024, avdiji2020}`
- "collaborative visual analytics (Chen et al., 2020; Chen et al., 2021; Kolloffel et al., 2011; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, kolloffel2011, hu2021}`
- "visual inquiry for sharing contextual knowledge (Sandberg, 2011)" → `\citep{sandberg2011}`
- "Presence, awareness, and representational guidance follow findings ... (Kolloffel et al., 2011; Chen et al., 2020; Chen et al., 2021)" → `\citep{kolloffel2011, chen2020, chen2021}`
- "Event models and visual representations ... (Chen et al., 2020; Chen et al., 2021; Hu & Chen, 2021)" → `\citep{chen2020, chen2021, hu2021}`
- "Content-level coherence builds on design theory ... (Avdiji et al., 2020) and canvas-based guidance ... (Schoormann et al., 2023)" → `\citep{avdiji2020, schoormann2023}`

For the "Examples of existing tools in literature" list, I can keep them as a list with citations.

For frameworks and libraries, I'll add them as @misc or @online entries:
- Elixir: @online
- Phoenix: @online
- Delta CRDTs: @online (GitHub repo)
- LiveView: @online

Now, for the BibTeX entries, let me write them carefully:

```bibtex
@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  volume  = {17},
  number  = {5},
  pages   = {543--551},
  doi     = {10.1057/ejis.2008.43}
}
```

Hmm, I don't know the exact volume/pages. Let me not fabricate details. I'll include what's known: author, title, year, journal, doi. For the DOI, I can use the `doi` field which natbib/plainnat will render as a URL if hyperref is loaded. Actually plainnat doesn't render doi field by default. Let me use `url` field with the doi link instead, or use `\usepackage{doi}`. Hmm.

Actually, with natbib + plainnat, the `doi` field is not printed. To keep it simple and correct, I'll put the DOI in the `url` field or use the `doi` package. Let me use the `doi` package which converts doi fields to clickable links. That's clean.

Actually, let me reconsider: `\usepackage{doi}` works with natbib and prints DOIs as links. Good.

For Aaen 2012 "Essence: Team-Based Software Innovation" — this appears to be a book or report. I'll make it @book or @misc. The markdown doesn't give a publisher. I'll use @misc with note or just @book without publisher. Let me use @misc to be safe... Actually, since it's cited as a book-like work, @book is fine but I don't have publisher info. Let me use @misc with a note. Hmm, actually for the report, I'll keep it simple: @book with just author/title/year, and note "Publisher information not specified in source document" — no, that's ugly. Let me just use @misc.

Actually, let me think about what's cleanest. I'll use:

```bibtex
@misc{aaen2012essence,
  author = {Aaen, Ivan},
  title  = {Essence: Team-Based Software Innovation},
  year   = {2012}
}
```

For books:
```bibtex
@book{osterwalder2010business,
  author    = {Osterwalder, Alexander and Pigneur, Yves},
  title     = {Business Model Generation},
  year      = {2010},
  publisher = {Wiley},
  url       = {https://www.strategyzer.com/books/business-model-generation}
}

@book{maurya2012running,
  author    = {Maurya, Ash},
  title     = {Running Lean},
  year      = {2012},
  publisher = {O'Reilly Media},
  url       = {https://leanspark.ai/leancanvas}
}
```

For conference papers:
```bibtex
@inproceedings{sandberg2011visual,
  author    = {Sandberg, F},
  title     = {Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge},
  booktitle = {Nordic Design Research Conference},
  year      = {2011},
  doi       = {10.21606/nordes.2011.028}
}

@article{schoormann2023guiding,
  author  = {Schoormann, Thorsten and M{\"o}ller, Frederik and Di Maria, Marco and Gro{\ss}e, N},
  title   = {Guiding Design Principle Projects: A Canvas for Young Design Science Researchers},
  journal = {Journal of Information Systems Education},
  year    = {2023},
  doi     = {10.62273/wkbc7575}
}

@inproceedings{roschnik2024approaching,
  author    = {Roschnik, A and Jaccard, D and Monnier, S and Missonier, S},
  title     = {Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform},
  booktitle = {ICIS Proceedings},
  year      = {2024}
}

@article{avdiji2020design,
  author  = {Avdiji, Hazbi and Elikan, Dina and Missonier, St{\'e}phanie and Pigneur, Yves},
  title   = {A Design Theory for Visual Inquiry Tools},
  journal = {Journal of the Association for Information Systems},
  year    = {2020},
  volume  = {21},
  number  = {6},
  doi     = {10.17705/1jais.00617}
}
```

Hmm, I need to be careful not to fabricate volume/number info. For Avdiji 2020, the DOI is 10.17705/1jais.00617. I know the JAIS article... I shouldn't fabricate. Let me include only what's in the source: author, title, journal, year, doi. That's safe.

For the collaboration papers:
```bibtex
@article{kolloffel2011comparing,
  author  = {Kolloffel, Bas and Eysink, Tessa H. S. and de Jong, Ton},
  title   = {Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning},
  journal = {International Journal of Computer-Supported Collaborative Learning},
  year    = {2011},
  volume  = {6},
  number  = {2},
  pages   = {223--251},
  doi     = {10.1007/s11412-011-9110-3}
}
```

Hmm, again, I know this paper has volume 6, pages 223-251, but I shouldn't fabricate. Let me just include author, title, journal, year, doi. Actually, the DOI is given in the source, so I'll include that. Volume/pages I'll omit to avoid fabrication.

```bibtex
@article{chen2020collaborative,
  author  = {Chen, Lin and Liang, Hai-Ning and Lu, Feiyu and Papangelis, Konstantinos and Man, Ka Lok and Yue, Yong},
  title   = {Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices},
  journal = {Human-centric Computing and Information Sciences},
  year    = {2020},
  volume  = {10},
  doi     = {10.1186/s13673-020-00253-7}
}
```

Hmm, volume 10 is correct for this one (it's article 40 in volume 10). But again, to be safe, I'll omit volume. Actually, the DOI is enough.

```bibtex
@article{chen2021large,
  author  = {Chen, Lin and Liang, Hai-Ning and Wang, Junxiu and Qu, Yuxuan and Yue, Yong},
  title   = {On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks},
  journal = {Sensors},
  year    = {2021},
  volume  = {21},
  number  = {24},
  doi     = {10.3390/s21248403}
}
```

Again, I'll omit volume/number to be safe. Just author, title, journal, year, doi.

```bibtex
@article{hu2021systematic,
  author  = {Hu, L and Chen, G},
  title   = {A Systematic Review of Visual Representations for Analyzing Collaborative Discourse},
  journal = {Educational Research Review},
  year    = {2021},
  doi     = {10.1016/j.edurev.2021.100403}
}
```

For frameworks:
```bibtex
@online{elixir,
  author = {Elixir Team},
  title  = {Elixir},
  year   = {2026},
  url    = {https://elixir-lang.org}
}

@online{phoenix,
  author = {Phoenix Framework},
  title  = {Phoenix},
  year   = {2026},
  url    = {https://www.phoenixframework.org}
}

@online{delta_crdt,
  author = {Kraan, Derek},
  title  = {Delta CRDTs},
  year   = {2026},
  url    = {https://github.com/derekkraan/delta_crdt_ex}
}

@online{liveview,
  author = {Phoenix Framework},
  title  = {Phoenix LiveView},
  year   = {2026},
  url    = {https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView}
}
```

Note: `@online` requires natbib to handle it. plainnat handles @online? Actually, plainnat is a bibtex style, and @online entries are supported by newer bibtex styles. plainnat does support @online I believe (it's in the natbib distribution). Yes, plainnat supports @online.

Hmm wait, actually there might be an issue: plainnat.bst handles @online? Let me think. plainnat.bst is from the natbib package and it does handle @online and @electronic. Yes, it does.

Now for the LaTeX document itself. Let me write a clean, professional document:

```latex
\documentclass[11pt,a4paper]{article}

% ---- Packages ----
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{geometry}
\geometry{margin=2.5cm}
\usepackage{graphicx}
\usepackage{xcolor}
\usepackage{booktabs}
\usepackage{enumitem}
\usepackage{parskip}
\usepackage{microtype}
\usepackage{doi}
\usepackage[round]{natbib}
\usepackage[hidelinks]{hyperref}
\usepackage{titlesec}
```

Wait, `\usepackage{doi}` — the doi package. It works with natbib. Good.

For the title, I'll create a custom title block:

```latex
\begin{titlepage}
  \centering
  \vspace*{2cm}
  {\Huge\bfseries Developing a Configurable Platform for Collaborative Visual Inquiry Tools\par}
  \vspace{0.5cm}
  {\LARGE The Problem--Solution Canvas\par}
  \vspace{2cm}
  {\large 9th Semester Project Proposal\par}
  \vspace{1cm}
  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
    \textbf{Student:} & Beltran Aceves \\
  \end{tabular}
  \vfill
  {\large \today\par}
\end{titlepage}
```

Hmm, but the user might want to keep the emails. Let me include them with \href.

Actually, let me reconsider the structure. The original has:
- Title
- 9th Semester
- Supervisor/Student with emails
- Project Summary
- Background
- Project Goals
- Functional Requirements (1-5)
- Non-Functional Requirements
- Deliverables
- Future Work
- References

I'll structure it as:
- Title page
- Abstract (Project Summary)
- Background
- Project Goals
- Functional Requirements
- Non-Functional Requirements
- Deliverables
- Future Work
- References (bibliography)

For the "Examples of existing tools" lists, I'll use itemize environments.

For the industry tools with URLs, I'll use \href.

Let me also think about the "quickly render with a webpage service" part. The user wants to render this quickly. Options:
1. Overleaf — upload the .tex and .bib files, compile with pdfLaTeX + BibTeX
2. A local service

I'll create a README with instructions for Overleaf, including:
- Create a new project, upload files
- Compile with pdfLaTeX (default) and BibTeX
- The natbib approach needs no special compiler settings

Let me also consider: should I use `biblatex` instead? With biblatex, the user needs to switch the compiler to biber in Overleaf. That's one extra step. natbib + bibtex works out of the box. I'll go with natbib.

Actually, wait. Let me reconsider. Modern Overleaf projects default to pdfLaTeX with "BibTeX" as the bibliography tool. natbib + plainnat + bibtex works perfectly with zero configuration. 

Let me now also think about whether to include a `\tableofcontents`. For a proposal document, a TOC is nice. I'll include it.

Let me write the full LaTeX document now.

One more consideration: the em-dash in "Problem–Solution Canvas" — I'll use `Problem--Solution` in LaTeX.

Also "9th Semester" — I'll put it on the title page.

Let me draft the full .tex file:

```latex
% ============================================================================
%  Project Proposal: A Configurable Platform for Collaborative Visual
%  Inquiry Tools — The Problem–Solution Canvas
%
%  Compile with pdfLaTeX + BibTeX (works out of the box on Overleaf).
% ============================================================================
\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts -------------------------------------------------------
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{microtype}

% --- Page layout ------------------------------------------------------------
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt, itemsep=2pt, parsep=0pt}

% --- Graphics & colors ------------------------------------------------------
\usepackage{xcolor}
\usepackage{graphicx}

% --- Tables -----------------------------------------------------------------
\usepackage{booktabs}

% --- Hyperlinks & DOIs ------------------------------------------------------
\usepackage[hidelinks]{hyperref}
\urlstyle{same}
\usepackage{doi}

% --- Citations --------------------------------------------------------------
\usepackage[round]{natbib}
\bibliographystyle{plainnat}

% --- Section formatting -----------------------------------------------------
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}

% --- Metadata ---------------------------------------------------------------
\title{Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem--Solution Canvas}
\author{Beltran Aceves}
\date{9th Semester}

\begin{document}

% --- Title page -------------------------------------------------------------
\begin{titlepage}
  \centering
  \vspace*{1.5cm}

  {\Huge\bfseries Developing a Configurable Platform for\\[0.3em] Collaborative Visual Inquiry Tools\par}
  \vspace{0.6cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{2.5cm}

  {\large 9th Semester Project Proposal\par}

  \vspace{1.5cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{ivan@cs.aau.dk} \\[0.5em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{baceve25@student.aau.dk} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}

\tableofcontents
\newpage

% --- Project Summary --------------------------------------------------------
\section{Project Summary}
...
```

Wait, the emails in the original have typos: `ivan@cs.af` and `baceve25@stduent.aau.dk`. These are clearly typos in the markdown (the mailto links are `mailto:ivan@cs.af` and `mailto:baceve25@stduent.aau.dk`). The display text is `ivan@cs.aau.dk` and `baceve25@student.aau.dk`. I'll use the correct display emails: `ivan@cs.aau.dk` and `baceve25@student.aau.dk`.

Now the body content. Let me convert each section:

**Project Summary:**
```latex
\section{Project Summary}

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem--Solution Canvas (PSC), developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems.

The platform will therefore let users:
\begin{itemize}
  \item define and share canvas templates (e.g., PSC variants);
  \item instantiate collaborative canvas instances that load and synchronize in real time;
  \item explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, and supports visualizing and traversing versions;
  \item automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event stream datasets;
  \item analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.
\end{itemize}

Implemented as a web application using the Elixir/Phoenix/Postgres stack, the platform will provide CRDT-based real-time collaboration, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.
```

**Background:**
```latex
\section{Background}

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem--Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the \emph{Essence} approach to software innovation \citep{aaen2008essence,aaen2012essence}, the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as Strategyzer \citep{...}...
```

Hmm, for the industry platforms, they're websites, not citations. I'll use \href for them.

```latex
Existing industry platforms such as \href{https://www.strategyzer.com}{Strategyzer}, \href{https://miro.com}{Miro}, \href{https://www.mural.co}{MURAL}, \href{https://canvanizer.com}{Canvanizer}, \href{https://leanspark.ai/leancanvas}{Lean Canvas}, and \href{https://designthinking.ideo.com/}{IDEO Design Thinking Tools} provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time or whether canvas content remains coherent and up to date. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas \citep{osterwalder2010business}, Lean Canvas \citep{maurya2012running}, Design Principle Canvas \citep{schoormann2023guiding}, and recent work on digital inquiry platforms \citep{roschnik2024approaching,avdiji2020design} and collaborative visual analytics \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}, as well as visual inquiry for sharing contextual knowledge \citep{sandberg2011visual}. This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, fine-grained interaction tracing, and content-level insights into a unified research-oriented platform.
```

Then the two lists:

```latex
\subsection{Examples of Existing Tools in Literature}
\begin{itemize}
  \item \textbf{Business Model Canvas} --- Osterwalder, A., \& Pigneur, Y. (2010). \emph{Business Model Generation}. \citep{osterwalder2010business}
  \item \textbf{Lean Canvas} --- Maurya, A. (2012). \emph{Running Lean}. \citep{maurya2012running}
  \item \textbf{Design Principle Canvas} --- Schoormann, T., et al. (2023). \emph{Guiding Design Principle Projects: A Canvas for Young Design Science Researchers}. \citep{schoormann2023guiding}
  \item \textbf{Digital Inquiry Platform concepts} --- Roschnik, A., et al. (2024). \emph{Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform}. See also Avdiji et al. (2020). \citep{roschnik2024approaching,avdiji2020design}
  \item \textbf{Collaborative visual inquiry and analytics research} --- Chen, L., et al. (2020). \emph{Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices}. See also Chen et al. (2021); Kolloffel et al. (2011); Hu \& Chen (2021). \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}
  \item \textbf{Visual inquiry and contextual knowledge sharing} --- Sandberg, F. (2011). \emph{Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge}. \citep{sandberg2011visual}
\end{itemize}

\subsection{Examples of Existing Tools in Industry}
\begin{itemize}
  \item \href{https://www.strategyzer.com/library?type=Tools}{Strategyzer}
  \item \href{https://miro.com}{Miro}
  \item \href{https://www.mural.co/templates}{MURAL}
  \item \href{https://canvanizer.com}{Canvanizer}
  \item \href{https://leanspark.ai/leancanvas}{Lean Canvas}
  \item \href{https://designthinking.ideo.com/}{Design Thinking tools (IDEO U)}
\end{itemize}
```

**Project Goals:**
```latex
\section{Project Goals}

The project focuses on building the MVP:
\begin{itemize}
  \item Development of the main web application with VIT core features;
  \item Implementation of the delta-based versioning system: explicit milestones/versions/commits in a traversable tree, with visualization and recorded pivot/bifurcation rationale;
  \item Implementation of the insights system for analyzing canvas content (coherence, staleness, quality signals, with optional LLM-enabled insights);
  \item Implementation of the analytics engine (automatic capture of interaction events and metrics) to lay the foundation for later study.
\end{itemize}
```

**Functional Requirements:**
```latex
\section{Functional Requirements}

\subsection{Core Tooling for VITs}
Design and implement core tooling for building Visual Inquiry Tools (VITs). This includes:
\begin{itemize}
  \item defining canvas structure (cells, relations, semantics) and templates;
  \item editor UI and components for creating and editing cells;
  \item template persistence and instantiation of canvases.
\end{itemize}

\subsection{Collaborative Workspaces}
Develop workspaces for real-time collaboration on canvases. This includes:
\begin{itemize}
  \item real-time collaborative editing using CRDTs with live document loading and conflict-free merges;
  \item per-user presence and cursor indicators, plus inline comments and discussion threads;
  \item sharing, access control, and session management for team sessions.
\end{itemize}

Presence, awareness, and representational guidance follow findings on collaborative inquiry learning and engagement with shared visual tasks \citep{kolloffel2011comparing,chen2020collaborative,chen2021large}.

\subsection{Delta Model \& Versioning}
A PSC, or any other VIT instance, evolves continuously during collaborative real-time sessions. This fluid evolution is normal and expected, but teams also need to explicitly mark that they have reached a meaningful point in the progress of their project or canvas.

The delta system provides this intentional versioning layer, to:
\begin{itemize}
  \item let users create explicit milestones/versions/commits (snapshots) of the canvas at chosen moments;
  \item organize versions in a tree-like manner supporting linear history as well as branches for pivots, bifurcations, and parallel alternatives;
  \item visualize and traverse the version tree (timeline/tree view, diff/compare between versions, restore or fork from any version);
  \item record the reason for each pivot or bifurcation (decision rationale, reinterpretation note, author, timestamp, parent link(s));
  \item provide tools to annotate and group deltas/versions for later analysis.
\end{itemize}

\subsection{Analytics \& Interaction Telemetry}
The platform provides an analytics engine that automatically captures all kinds of events and metrics from users interacting with the system, so they can be analyzed later:
\begin{itemize}
  \item passively log interaction events (edits, navigation, presence, comments, version operations, insight views) with order, frequency/distribution, and metadata (who, when, where in the canvas, session/device context);
  \item expose exportable event streams and lightweight aggregation APIs for research use;
  \item enable studies of user archetypes, framing patterns, collaboration dynamics, and outcome correlations.
\end{itemize}

Event models and visual representations for collaborative discourse build on prior work in visual analytics and discourse analysis \citep{chen2020collaborative,chen2021large,hu2021systematic}.

\subsection{Insights \& Content Analysis}
Analyze the contents of a given PSC to support reflection and convergence, complementing the interaction-level analytics in Section~\ref{sec:analytics}:
\begin{itemize}
  \item detect cells deviating from the central theme or problem framing of the canvas;
  \item detect old/stale cells (e.g., untouched, superseded, or inconsistent with recent pivots/decisions);
  \item surface coherence and quality signals (e.g., contradictions, gaps, duplicates across cells);
  \item provide LLM-enabled insights where appropriate (e.g., summaries, suggestions, theme-drift explanations), designed as an optional, pluggable layer over deterministic heuristics so the platform remains usable without an LLM provider.
\end{itemize}

Content-level coherence builds on design theory for visual inquiry tools \citep{avdiji2020design} and canvas-based guidance for design projects \citep{schoormann2023guiding}.
```

I need to add a label to the analytics section: `\label{sec:analytics}`.

**Non-Functional Requirements:**
```latex
\section{Non-Functional Requirements}
\begin{itemize}
  \item The platform should be built using the Elixir/Phoenix stack for scalability and real-time capabilities.
  \item The system should be designed for extensibility to support future features and different types of VIT, including new insight detectors and LLM providers.
  \item The user interface should be intuitive and responsive to facilitate collaboration and ease of use, including support for both desktop and mobile devices.
  \item The platform should ensure data integrity and consistency during real-time collaboration, using CRDTs for conflict-free merging of changes.
  \item The analytics infrastructure should be designed to efficiently capture and store interaction data while minimizing performance overhead on the user experience.
  \item The insights system should run efficiently alongside editing (e.g., asynchronous/on-demand analysis) and keep LLM usage optional, privacy-aware, and clearly attributed, so canvases remain fully usable without external AI services.
  \item The system should be easy to deploy and maintain, with clear documentation for both users and developers.
\end{itemize}
```

**Deliverables:**
```latex
\section{Deliverables}
\begin{itemize}
  \item A working web application built with Elixir/Phoenix;
  \item Project documentation and deployment guide;
  \item Support for:
  \begin{itemize}
    \item configurable visual inquiry templates;
    \item collaborative canvas instances;
    \item delta-based pivot versioning;
    \item insights system for canvas content analysis (theme deviation, stale cells, coherence signals, with optional LLM-enabled insights);
    \item a basic analytics engine automatically capturing user interaction events and metrics, with exportable streams for later analysis;
  \end{itemize}
  \item A written report describing:
  \begin{itemize}
    \item design decisions;
    \item system architecture;
    \item and implications for supporting visual inquiry and innovation.
  \end{itemize}
\end{itemize}
```

**Future Work:**
```latex
\section{Future Work}

The following are out of scope for the MVP but are natural next steps once the core platform is in place.

\paragraph{Experiments on user behavior.}
Design and run studies using the analytics engine to look at patterns of use, problem framing, and solution development; such as user archetypes, framing patterns, collaboration dynamics, and how they relate to outcomes. This would also mean scaling up the analytics side: experiment tooling, aggregation APIs, and dataset exports for larger studies.

\paragraph{Non-table canvases.}
The MVP assumes table-like canvases made of cells. Later we want templates that are not grids at all: a background image or SVG with floating text inputs placed on top of it. This would support more visual or spatial VITs (maps, diagrams, annotated pictures) using the same collaboration, versioning, and analytics foundations.
```

**References:**
```latex
\section{References}
\bibliography{references}
```

Wait, I should organize the references. The original has subsections: Frameworks and Libraries, Core Concepts, Visual Inquiry Tools and Collaborative Inquiry, Collaboration Visual Analytics and Interaction Analysis. With a single .bib file and plainnat, the references will be alphabetical. That's fine and standard. I could add \nocite for all entries. Since I cite everything in the text, all entries will appear. Let me double check: do I cite all entries?

- aaen2008essence ✓ (Background)
- aaen2012essence ✓ (Background)
- osterwalder2010business ✓ (Background + literature list)
- maurya2012running ✓ (Background + literature list)
- schoormann2023guiding ✓ (Background + literature list + insights)
- roschnik2024approaching ✓ (Background + literature list)
- avdiji2020design ✓ (Background + literature list + insights)
- chen2020collaborative ✓ (Background + literature list + workspaces + analytics)
- chen2021large ✓ (Background + literature list + workspaces + analytics)
- kolloffel2011comparing ✓ (Background + literature list + workspaces)
- hu2021systematic ✓ (Background + literature list + analytics)
- sandberg2011visual ✓ (Background + literature list)
- elixir ✓ (need to cite in text)
- phoenix ✓ (need to cite in text)
- delta_crdt ✓ (need to cite in text)
- liveview ✓ (need to cite in text)

For the frameworks, I should cite them in the text. In the Project Summary: "Implemented as a web application using the Elixir/Phoenix/Postgres stack" — I can add citations there: `\citep{elixir,phoenix}`. And for CRDT-based real-time collaboration: `\citep{delta_crdt}`. And LiveView: maybe in the summary or background. Let me add them naturally:

"Implemented as a web application using the Elixir/Phoenix/Postgres stack \citep{elixir,phoenix}, the platform will provide CRDT-based real-time collaboration \citep{delta_crdt}, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents."

And LiveView: "using the Elixir/Phoenix stack \citep{elixir,phoenix,liveview}" — hmm, LiveView is part of Phoenix. Let me cite it in the summary too or in the workspaces section. Actually, let me cite it in the summary: `\citep{elixir,phoenix,liveview}`. That works.

Now, the .bib file. Let me write it carefully with proper LaTeX escaping (e.g., `{\"o}` or `{\"o}` for ö, `\&` for &).

For Schoormann: Möller → M{\"o}ller, Große → Gro{\ss}e. Actually "Große" — the markdown says "Große, N." Let me write Gro{\ss}e.

For Avdiji: Stéphanie → St{\'e}phanie.

Now, one issue: `\usepackage{doi}` — the doi package. It works with natbib and converts doi fields to clickable links. Good.

Also, I should think about whether `plainnat` handles `@online`. Yes, plainnat.bst supports @online entries (it treats them like @misc with url). Good.

Let me also add `\usepackage{url}` — actually hyperref loads url internally. `\urlstyle{same}` makes URLs use the same font. Good.

Now, about the README for Overleaf. Let me write clear instructions:

```markdown
# LaTeX version of the Project Proposal

This folder contains a LaTeX version of `docs/project_proposal.md`, ready to compile on Overleaf (or any LaTeX distribution).

## Files
- `project_proposal.tex` — main document
- `references.bib` — BibTeX bibliography

## Quick start on Overleaf
1. Go to https://www.overleaf.com and create a new project (Blank Project).
2. Upload `project_proposal.tex` and `references.bib` (or copy-paste the contents).
3. Make sure the compiler is set to **pdfLaTeX** (default) and the bibliography tool is **BibTeX** (default).
4. Click **Recompile**. The bibliography is generated automatically.

## Local compilation
```bash
pdflatex project_proposal
bibtex project_proposal
pdflatex project_proposal
pdflatex project_proposal
```

## Notes
- Citations use `natbib` with the `plainnat` style (author–year).
- DOIs are rendered as clickable links via the `doi` package.
- All references from the markdown are included in `references.bib`.
```

Now, where to put these files? I'll create `docs/latex/` folder with:
- `project_proposal.tex`
- `references.bib`
- `README.md`

Let me also double-check the LaTeX for any issues:

1. `\citep{...}` with multiple keys — fine.
2. The `doi` package — `\usepackage{doi}`. Fine.
3. `\href{mailto:...}` — fine with hyperref.
4. `\paragraph` — fine.
5. `\tableofcontents` — fine.
6. Title page — fine.

One thing: `\usepackage[round]{natbib}` gives (Author, Year) style citations. Good for a proposal.

Also, I should consider adding `\setlength{\parskip}` via parskip package — done.

Let me also think about the em-dash usage. In the title: "The Problem–Solution Canvas" uses an en-dash. In LaTeX: `Problem--Solution`.

Also "9th Semester" — I'll put it on the title page and in the date.

Let me also handle the "Project Summary" — should it be an abstract? I'll keep it as a section titled "Project Summary" to match the original. Actually, I could use `\begin{abstract}` but the original calls it "Project Summary". Let me keep it as a section for fidelity.

Hmm, one more thought: should I use `report` class instead of `article`? The document has sections (not chapters), so `article` is appropriate.

Let me also add a nice touch: `\usepackage{setspace}` with `\onehalfspacing`? That's common for reports. Hmm, it might make it longer. Let me keep single spacing but with parskip. Actually, for a proposal document, onehalfspacing is common in academic settings. But to keep it simple and compact, I'll skip it. Actually, let me add it as an option — no, keep it simple.

Let me also think about fonts. Default Computer Modern is fine. I could use `\usepackage{lmodern}` for better rendering. Let me add lmodern.

Now let me also double check: the user said "quickly render with a webpage service". Maybe they also want to know about services that render LaTeX in the browser without an account. There are services like:
- Overleaf (needs account, free)
- LaTeX.Online (renders in browser)
- Papeeria
- TeXLive.net (renders LaTeX snippets via URL)

I'll mention Overleaf primarily in the README, and maybe briefly mention alternatives.

Let me now create the files. I'll create:
1. `docs/latex/project_proposal.tex`
2. `docs/latex/references.bib`
3. `docs/latex/README.md`

Let me write the complete .tex file content:

Actually, let me reconsider the title page. The original title is "Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem–Solution Canvas". I'll split it across lines nicely.

Let me also add a footer with page numbers — default article class has page numbers. Good.

Let me write everything now. I'll be careful with special characters:
- `&` → `\&`
- `%` → `\%` (none in text I think)
- `#` → `\#` (none)
- `_` → `\_` (none in text)
- `~` → `\textasciitilde` (none)
- `$` → `\$` (none)

In the bib file:
- `&` → `\&` (e.g., "Osterwalder, A., & Pigneur, Y." → in bib, author field uses "and" so no & needed)
- `ö` → `{\"o}`
- `é` → `{\'e}`
- `ß` → `{\ss}`

Let me write the bib entries:

```bibtex
% ============================================================================
%  References for the Project Proposal
%  Compiled with BibTeX using the plainnat style (natbib).
% ============================================================================

% --- Frameworks and Libraries ------------------------------------------------

@online{elixir,
  author = {{Elixir Team}},
  title  = {Elixir},
  year   = {2026},
  url    = {https://elixir-lang.org}
}

@online{phoenix,
  author = {{Phoenix Framework}},
  title  = {Phoenix},
  year   = {2026},
  url    = {https://www.phoenixframework.org}
}

@online{delta_crdt,
  author = {Kraan, Derek},
  title  = {Delta CRDTs},
  year   = {2026},
  url    = {https://github.com/derekkraan/delta_crdt_ex}
}

@online{liveview,
  author = {{Phoenix Framework}},
  title  = {Phoenix LiveView},
  year   = {2026},
  url    = {https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView}
}

% --- Core Concepts -----------------------------------------------------------

@article{aaen2008essence,
  author  = {Aaen, Ivan},
  title   = {Essence: Facilitating Software Innovation},
  journal = {European Journal of Information Systems},
  year    = {2008},
  doi     = {10.1057/ejis.2008.43}
}

@misc{aaen2012essence,
  author = {Aaen, Ivan},
  title  = {Essence: Team-Based Software Innovation},
  year   = {2012}
}

@book{osterwalder2010business,
  author    = {Osterwalder, Alexander and Pigneur, Yves},
  title     = {Business Model Generation},
  year      = {2010},
  publisher = {Wiley},
  url       = {https://www.strategyzer.com/books/business-model-generation}
}

@book{maurya2012running,
  author    = {Maurya, Ash},
  title     = {Running Lean},
  year      = {2012},
  publisher = {O'Reilly Media},
  url       = {https://leanspark.ai/leancanvas}
}

% --- Visual Inquiry Tools and Collaborative Inquiry --------------------------

@inproceedings{sandberg2011visual,
  author    = {Sandberg, F},
  title     = {Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge},
  booktitle = {Nordic Design Research Conference},
  year      = {2011},
  doi       = {10.21606/nordes.2011.028}
}

@article{schoormann2023guiding,
  author  = {Schoormann, Thorsten and M{\"o}ller, Frederik and Di Maria, Marco and Gro{\ss}e, N},
  title   = {Guiding Design Principle Projects: A Canvas for Young Design Science Researchers},
  journal = {Journal of Information Systems Education},
  year    = {2023},
  doi     = {10.62273/wkbc7575}
}

@inproceedings{roschnik2024approaching,
  author    = {Roschnik, A and Jaccard, D and Monnier, S and Missonier, S},
  title     = {Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform},
  booktitle = {ICIS Proceedings},
  year      = {2024}
}

@article{avdiji2020design,
  author  = {Avdiji, Hazbi and Elikan, Dina and Missonier, St{\'e}phanie and Pigneur, Yves},
  title   = {A Design Theory for Visual Inquiry Tools},
  journal = {Journal of the Association for Information Systems},
  year    = {2020},
  doi     = {10.17705/1jais.00617}
}

% --- Collaboration, Visual Analytics, and Interaction Analysis ---------------

@article{kolloffel2011comparing,
  author  = {Kolloffel, Bas and Eysink, Tessa H. S. and de Jong, Ton},
  title   = {Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning},
  journal = {International Journal of Computer-Supported Collaborative Learning},
  year    = {2011},
  doi     = {10.1007/s11412-011-9110-3}
}

@article{chen2020collaborative,
  author  = {Chen, Lin and Liang, Hai-Ning and Lu, Feiyu and Papangelis, Konstantinos and Man, Ka Lok and Yue, Yong},
  title   = {Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices},
  journal = {Human-centric Computing and Information Sciences},
  year    = {2020},
  doi     = {10.1186/s13673-020-00253-7}
}

@article{chen2021large,
  author  = {Chen, Lin and Liang, Hai-Ning and Wang, Junxiu and Qu, Yuxuan and Yue, Yong},
  title   = {On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks},
  journal = {Sensors},
  year    = {2021},
  doi     = {10.3390/s21248403}
}

@article{hu2021systematic,
  author  = {Hu, L and Chen, G},
  title   = {A Systematic Review of Visual Representations for Analyzing Collaborative Discourse},
  journal = {Educational Research Review},
  year    = {2021},
  doi     = {10.1016/j.edurev.2021.100403}
}
```

Wait, for `@online` with `author = {{Elixir Team}}` — the double braces prevent BibTeX from interpreting "Elixir Team" as "Team, Elixir". Good.

Hmm, one concern: `plainnat.bst` and `@online` — plainnat does support @online. Let me double check... plainnat.bst from natbib distribution: it handles @article, @book, @booklet, @inbook, @incollection, @inproceedings, @conference, @manual, @mastersthesis, @misc, @phdthesis, @proceedings, @techreport, @unpublished, @online, @electronic, @www. Yes, plainnat supports @online. 

Now, one more consideration: the `doi` package. When using natbib with plainnat, the doi package hooks into the bibliography to print DOIs. It works. But there's a subtlety: the doi package requires the `url` package (loaded by hyperref). Fine.

Actually, let me reconsider whether to use the `doi` package or just put DOIs in `url` fields. The `doi` package is simpler and cleaner. Let me keep it.

Now, let me also think about whether the user might want to compile this locally too. The README covers both.

Let me also consider adding a `\section*{Abstract}` vs keeping "Project Summary". I'll keep "Project Summary" as the section title to match the original document.

One more thing: the original has "9th Semester" right after the title. I'll include it on the title page.

Let me also think about the date. The current date is 2026-09-17. I'll use `\today` which will render the compile date. That's fine.

Now let me create the files. Let me also verify the folder structure — I'll create `docs/latex/`.

Actually, wait — should I ask the user any clarifying questions? The request is fairly clear: transform the markdown into a LaTeX/Overleaf document. I could ask about:
- Whether they want a specific document class (article vs report)
- Whether they want the full bibliography as BibTeX
- Whether they want it in a specific folder

But these are minor decisions I can make sensibly. The user said "quickly render with a webpage service" which strongly implies Overleaf. I'll make reasonable choices and document them. I don't think I need to ask questions — the task is clear enough. Let me just do it well.

Let me create the three files now.

Actually, let me reconsider one thing about the title page layout. Let me make it clean:

```latex
\begin{titlepage}
  \centering
  \vspace*{2cm}

  {\Huge\bfseries Developing a Configurable Platform for Collaborative Visual Inquiry Tools\par}
  \vspace{0.8cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{3cm}

  {\large 9th Semester --- Project Proposal\par}

  \vspace{2cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{\texttt{ivan@cs.aau.dk}} \\[0.8em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{\texttt{baceve25@student.aau.dk}} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}
```

Good. Now the full document. Let me write it out completely and carefully.

Also, I want to double-check the `\citep` usage in the "Examples of Existing Tools in Literature" list. Since the list items already contain the full citation info (author, year, title), adding `\citep` would duplicate. Hmm. Let me think...

Option A: Keep the list items as descriptive text with the full citation info, and add `\citep` at the end for the bibliography entry. This creates redundancy in the list but ensures the bibliography is complete.

Option B: Make the list items reference the bibliography entries only, e.g., "Business Model Canvas — \citet{osterwalder2010business}". This is cleaner but loses the descriptive titles.

Since all these works are already cited in the Background section text, the bibliography will be complete even without citing them in the lists. So in the lists, I can keep the descriptive text as-is (matching the original markdown) without adding \citep. That avoids redundancy. The Background paragraph already cites all of them.

Wait, let me verify: does the Background paragraph cite ALL of them?
- osterwalder2010business ✓ ("Business Model Canvas (Osterwalder & Pigneur, 2010)")
- maurya2012running ✓ ("Lean Canvas (Maurya, 2012)")
- schoormann2023guiding ✓ ("Design Principle Canvas (Schoormann et al., 2023)")
- roschnik2024approaching ✓ ("digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020)")
- avdiji2020design ✓ (same)
- chen2020collaborative ✓ ("collaborative visual analytics (Chen et al., 2020; ...)")
- chen2021large ✓
- kolloffel2011comparing ✓
- hu2021systematic ✓
- sandberg2011visual ✓ ("visual inquiry for sharing contextual knowledge (Sandberg, 2011)")

Yes, all are cited in the Background. So the lists can be descriptive without \citep. 

But wait — there's a subtlety with natbib: if an entry is cited but the list also mentions it, that's fine. The bibliography will include all cited entries. Good.

Hmm, but actually, for the "Examples of Existing Tools in Literature" list, it might be nice to keep the full citation info in the list (as the original does) AND have them in the bibliography. The original markdown has the full info in the list. I'll keep the list items as in the original (with author, year, title) but formatted nicely. Since they're already cited in the text, the bibliography will have them. No \citep needed in the list. 

Now, let me also make sure I handle the "See also" references in the list items. E.g., "See also Avdiji et al. (2020)." I'll keep those as text.

OK let me also think about whether to add `\label` for cross-references. In the Insights section, it references "section 4" (Analytics & Interaction Telemetry). I'll add `\label{sec:analytics}` to the analytics section and reference it as `Section~\ref{sec:analytics}`.

Now, let me write the final files.

One more consideration on packages: `\usepackage{doi}` might conflict with hyperref if loaded in wrong order. The doi package should be loaded after hyperref? Actually, the doi package documentation says to load it after natbib. Order: natbib, then doi, then hyperref? Hmm. Let me think. The doi package redefines the bibliography to add DOI links. It works with hyperref. Common order: load hyperref last (it's usually loaded last). The doi package can be loaded before or after hyperref; it uses \href internally if hyperref is loaded. To be safe: load natbib, then doi, then hyperref last. Actually, hyperref should generally be loaded last among these. Let me do:

```latex
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}
\usepackage[hidelinks]{hyperref}
```

Hmm, but the doi package documentation says: "The package should be loaded after natbib and before hyperref" — actually I recall the doi package works fine either way. Let me load doi after natbib and before hyperref. That's the documented order.

Wait, actually there's a known issue: if hyperref is loaded after doi, the doi links work. If hyperref is loaded before doi, doi still works but might warn. The recommended order is natbib → doi → hyperref. Let me use that.

Also `\urlstyle{same}` should come after hyperref (or after url package). Let me put it after hyperref.

Let me finalize the preamble:

```latex
\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts ---
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{lmodern}
\usepackage{microtype}

% --- Page layout ---
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt,itemsep=2pt,parsep=0pt}

% --- Graphics ---
\usepackage{graphicx}
\usepackage{xcolor}

% --- Tables ---
\usepackage{booktabs}

% --- Citations & bibliography ---
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}

% --- Hyperlinks ---
\usepackage[hidelinks]{hyperref}
\urlstyle{same}

% --- Section formatting ---
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}
```

Hmm, `\usepackage{graphicx}` and `booktabs` aren't strictly needed (no figures/tables), but harmless. Actually, let me drop booktabs and graphicx to keep it minimal... Actually, keeping them doesn't hurt and allows future additions. I'll keep graphicx but drop booktabs since there are no tables. Actually, let me keep both minimal — I'll keep graphicx (common) and drop booktabs. Hmm, actually let me just keep the preamble lean: drop both. No wait — the user may add figures later. Let me keep graphicx. Drop booktabs.

Actually, you know what, let me keep it simple and include only what's used plus a couple of common ones (graphicx, xcolor). Fine.

Let me now also double check `\titleformat` — titlesec with `\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}`. This is fine.

Now writing the body. Let me be careful with the em-dashes in the text: "---" for em-dash, "--" for en-dash.

In "Problem–Solution Canvas" → `Problem--Solution Canvas`.

Let me write the complete file now.

Also, I realize I should double-check: does the user want me to also keep the markdown file? Yes, I'm creating new files alongside, not modifying the markdown. Good.

Let me also think about the README content more. The user said "quickly render with a webpage service". I'll write the README to cover:
1. Overleaf quick start (main path)
2. Alternative: local compilation
3. Alternative web services briefly

Let me write it.

Now, let me create all three files. I'll use create_file for each.

Let me write out the complete .tex content:

```latex
% ============================================================================
%  Project Proposal
%  Developing a Configurable Platform for Collaborative Visual Inquiry Tools:
%  The Problem–Solution Canvas
%
%  Compile with pdfLaTeX + BibTeX (default settings on Overleaf).
%  Bibliography: references.bib (natbib / plainnat, author–year style).
% ============================================================================

\documentclass[11pt,a4paper]{article}

% --- Encoding & fonts -------------------------------------------------------
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage[english]{babel}
\usepackage{lmodern}
\usepackage{microtype}

% --- Page layout ------------------------------------------------------------
\usepackage[a4paper,margin=2.5cm]{geometry}
\usepackage{parskip}
\usepackage{enumitem}
\setlist{topsep=2pt,itemsep=2pt,parsep=0pt}

% --- Graphics & colors ------------------------------------------------------
\usepackage{graphicx}
\usepackage{xcolor}

% --- Citations & bibliography -----------------------------------------------
\usepackage[round]{natbib}
\bibliographystyle{plainnat}
\usepackage{doi}

% --- Hyperlinks -------------------------------------------------------------
\usepackage[hidelinks]{hyperref}
\urlstyle{same}

% --- Section formatting -----------------------------------------------------
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries}{\thesection}{0.6em}{}
\titleformat{\subsection}{\large\bfseries}{\thesubsection}{0.6em}{}

% ============================================================================
\begin{document}

% --- Title page -------------------------------------------------------------
\begin{titlepage}
  \centering
  \vspace*{2cm}

  {\Huge\bfseries Developing a Configurable Platform for\\[0.4em] Collaborative Visual Inquiry Tools\par}
  \vspace{0.8cm}
  {\LARGE The Problem--Solution Canvas\par}

  \vspace{3cm}

  {\large 9th Semester --- Project Proposal\par}

  \vspace{2cm}

  \begin{tabular}{rl}
    \textbf{Supervisor:} & Ivan Aaen \\
                         & \href{mailto:ivan@cs.aau.dk}{\texttt{ivan@cs.aau.dk}} \\[0.8em]
    \textbf{Student:}    & Beltran Aceves \\
                         & \href{mailto:baceve25@student.aau.dk}{\texttt{baceve25@student.aau.dk}} \\
  \end{tabular}

  \vfill

  {\large \today\par}

  \vspace*{1cm}
\end{titlepage}

% --- Table of contents ------------------------------------------------------
\tableofcontents
\newpage

% --- Project Summary --------------------------------------------------------
\section{Project Summary}

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem--Solution Canvas (PSC), developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems.

The platform will therefore let users:
\begin{itemize}
  \item define and share canvas templates (e.g., PSC variants);
  \item instantiate collaborative canvas instances that load and synchronize in real time;
  \item explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, and supports visualizing and traversing versions;
  \item automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event stream datasets;
  \item analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.
\end{itemize}

Implemented as a web application using the Elixir/Phoenix/Postgres stack \citep{elixir,phoenix,liveview}, the platform will provide CRDT-based real-time collaboration \citep{delta_crdt}, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.

% --- Background -------------------------------------------------------------
\section{Background}

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem--Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the \emph{Essence} approach to software innovation \citep{aaen2008essence,aaen2012essence}, the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as \href{https://www.strategyzer.com}{Strategyzer}, \href{https://miro.com}{Miro}, \href{https://www.mural.co}{MURAL}, \href{https://canvanizer.com}{Canvanizer}, \href{https://leanspark.ai/leancanvas}{Lean Canvas}, and \href{https://designthinking.ideo.com/}{IDEO Design Thinking Tools} provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time or whether canvas content remains coherent and up to date. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas \citep{osterwalder2010business}, Lean Canvas \citep{maurya2012running}, Design Principle Canvas \citep{schoormann2023guiding}, and recent work on digital inquiry platforms \citep{roschnik2024approaching,avdiji2020design} and collaborative visual analytics \citep{chen2020collaborative,chen2021large,kolloffel2011comparing,hu2021systematic}, as well as visual inquiry for sharing contextual knowledge \citep{sandberg2011visual}. This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, fine-grained interaction tracing, and content-level insights into a unified research-oriented platform.

\subsection{Examples of Existing Tools in Literature}

\begin{itemize}
  \item \textbf{Business Model Canvas} --- Osterwalder, A., \& Pigneur, Y. (2010). \emph{Business Model Generation}.
  \item \textbf{Lean Canvas} --- Maurya, A. (2012). \emph{Running Lean}.
  \item \textbf{Design Principle Canvas} --- Schoormann, T., et al. (2023). \emph{Guiding Design Principle Projects: A Canvas for Young Design Science Researchers}.
  \item \textbf{Digital Inquiry Platform concepts} --- Roschnik, A., et al. (2024). \emph{Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform}. See also Avdiji et al. (2020).
  \item \textbf{Collaborative visual inquiry and analytics research} --- Chen, L., et al. (2020). \emph{Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices}. See also Chen et al. (2021); Kolloffel et al. (2011); Hu \& Chen (2021).
  \item \textbf{Visual inquiry and contextual knowledge sharing} --- Sandberg, F. (2011). \emph{Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge}.
\end{itemize}

\subsection{Examples of Existing Tools in Industry}

\begin{itemize}
  \item \href{https://www.strategyzer.com/library?type=Tools}{Strategyzer}
  \item \href{https://miro.com}{Miro}
  \item \href{https://www.mural.co/templates}{MURAL}
  \item \href{https://canvanizer.com}{Canvanizer}
  \item \href{https://leanspark.ai/leancanvas}{Lean Canvas}
  \item \href{https://designthinking.ideo.com/}{Design Thinking Tools (IDEO U)}
\end{itemize}

% --- Project Goals ----------------------------------------------------------
\section{Project Goals}

The project focuses on building the MVP:
\begin{itemize}
  \item development of the main web application with VIT core features;
  \item implementation of the delta-based versioning system: explicit milestones/versions/commits in a traversable tree, with visualization and recorded pivot/bifurcation rationale;
  \item implementation of the insights system for analyzing canvas content (coherence, staleness, quality signals, with optional LLM-enabled insights);
  \item implementation of the analytics engine (automatic capture of interaction events and metrics) to lay the foundation for later study.
\end{itemize}

% --- Functional Requirements ------------------------------------------------
\section{Functional Requirements}

\subsection{Core Tooling for VITs}

Design and implement core tooling for building Visual Inquiry Tools (VITs). This includes:
\begin{itemize}
  \item defining canvas structure (cells, relations, semantics) and templates;
  \item editor UI and components for creating and editing cells;
  \item template persistence and instantiation of canvases.
\end{itemize}

\subsection{Collaborative Workspaces}

Develop workspaces for real-time collaboration on canvases. This includes:
\begin{itemize}
  \item real-time collaborative editing using CRDTs with live document loading and conflict-free merges;
  \item per-user presence and cursor indicators, plus inline comments and discussion threads;
  \item sharing, access control, and session management for team sessions.
\end{itemize}

Presence, awareness, and representational guidance follow findings on collaborative inquiry learning and engagement with shared visual tasks \citep{kolloffel2011comparing,chen2020collaborative,chen2021large}.

\subsection{Delta Model \& Versioning}

A PSC, or any other VIT instance, evolves continuously during collaborative real-time sessions. This fluid evolution is normal and expected, but teams also need to explicitly mark that they have reached a meaningful point in the progress of their project or canvas.

The delta system provides this intentional versioning layer, to:
\begin{itemize}
  \item let users create explicit milestones/versions/commits (snapshots) of the canvas at chosen moments;
  \item organize versions in a tree-like manner supporting linear history as well as branches for pivots, bifurcations, and parallel alternatives;
  \item visualize and traverse the version tree (timeline/tree view, diff/compare between versions, restore or fork from any version);
  \item record the reason for each pivot or bifurcation (decision rationale, reinterpretation note, author, timestamp, parent link(s));
  \item provide tools to annotate and group deltas/versions for later analysis.
\end{itemize}

\subsection{Analytics \& Interaction Telemetry}
\label{sec:analytics}

The platform provides an analytics engine that automatically captures all kinds of events and metrics from users interacting with the system, so they can be analyzed later:
\begin{itemize}
  \item passively log interaction events (edits, navigation, presence, comments, version operations, insight views) with order, frequency/distribution, and metadata (who, when, where in the canvas, session/device context);
  \item expose exportable event streams and lightweight aggregation APIs for research use;
  \item enable studies of user archetypes, framing patterns, collaboration dynamics, and outcome correlations.
\end{itemize}

Event models and visual representations for collaborative discourse build on prior work in visual analytics and discourse analysis \citep{chen2020collaborative,chen2021large,hu2021systematic}.

\subsection{Insights \& Content Analysis}

Analyze the contents of a given PSC to support reflection and convergence, complementing the interaction-level analytics in Section~\ref{sec:analytics}:
\begin{itemize}
  \item detect cells deviating from the central theme or problem framing of the canvas;
  \item detect old/stale cells (e.g., untouched, superseded, or inconsistent with recent pivots/decisions);
  \item surface coherence and quality signals (e.g., contradictions, gaps, duplicates across cells);
  \item provide LLM-enabled insights where appropriate (e.g., summaries, suggestions, theme-drift explanations), designed as an optional, pluggable layer over deterministic heuristics so the platform remains usable without an LLM provider.
\end{itemize}

Content-level coherence builds on design theory for visual inquiry tools \citep{avdiji2020design} and canvas-based guidance for design projects \citep{schoormann2023guiding}.

% --- Non-Functional Requirements --------------------------------------------
\section{Non-Functional Requirements}

\begin{itemize}
  \item The platform should be built using the Elixir/Phoenix stack for scalability and real-time capabilities.
  \item The system should be designed for extensibility to support future features and different types of VIT, including new insight detectors and LLM providers.
  \item The user interface should be intuitive and responsive to facilitate collaboration and ease of use, including support for both desktop and mobile devices.
  \item The platform should ensure data integrity and consistency during real-time collaboration, using CRDTs for conflict-free merging of changes.
  \item The analytics infrastructure should be designed to efficiently capture and store interaction data while minimizing performance overhead on the user experience.
  \item The insights system should run efficiently alongside editing (e.g., asynchronous/on-demand analysis) and keep LLM usage optional, privacy-aware, and clearly attributed, so canvases remain fully usable without external AI services.
  \item The system should be easy to deploy and maintain, with clear documentation for both users and developers.
\end{itemize}

% --- Deliverables -----------------------------------------------------------
\section{Deliverables}

\begin{itemize}
  \item A working web application built with Elixir/Phoenix;
  \item Project documentation and deployment guide;
  \item Support for:
  \begin{itemize}
    \item configurable visual inquiry templates;
    \item collaborative canvas instances;
    \item delta-based pivot versioning;
    \item insights system for canvas content analysis (theme deviation, stale cells, coherence signals, with optional LLM-enabled insights);
    \item a basic analytics engine automatically capturing user interaction events and metrics, with exportable streams for later analysis;
  \end{itemize}
  \item A written report describing:
  \begin{itemize}
    \item design decisions;
    \item system architecture;
    \item and implications for supporting visual inquiry and innovation.
  \end{itemize}
\end{itemize}

% --- Future Work ------------------------------------------------------------
\section{Future Work}

The following are out of scope for the MVP but are natural next steps once the core platform is in place.

\paragraph{Experiments on user behavior.}
Design and run studies using the analytics engine to look at patterns of use, problem framing, and solution development; such as user archetypes, framing patterns, collaboration dynamics, and how they relate to outcomes. This would also mean scaling up the analytics side: experiment tooling, aggregation APIs, and dataset exports for larger studies.

\paragraph{Non-table canvases.}
The MVP assumes table-like canvases made of cells. Later we want templates that are not grids at all: a background image or SVG with floating text inputs placed on top of it. This would support more visual or spatial VITs (maps, diagrams, annotated pictures) using the same collaboration, versioning, and analytics foundations.

% --- References -------------------------------------------------------------
\section{References}
\bibliography{references}

\end{document}
```

Wait, there's an issue with `\label{sec:analytics}` placement — I put it after `\subsection{Analytics \& Interaction Telemetry}`. That's correct placement (right after the section command).

Hmm, one thing: `\citep{elixir,phoenix,liveview}` in the summary — the citation will render as (Elixir Team, 2026; Phoenix Framework, 2026; Phoenix Framework, 2026). Two entries by "Phoenix Framework" — that's fine, they'll be distinguished by year (both 2026). Hmm, actually with the same author and year, BibTeX will add "a" and "b" suffixes. That's fine.

Actually wait, there might be an issue: `@online{phoenix, author = {{Phoenix Framework}}}` and `@online{liveview, author = {{Phoenix Framework}}}` — same author, same year 2026 → they'll get 2026a and 2026b. Fine.

Let me reconsider the year for the online entries. The current date is 2026-09-17. Using 2026 is reasonable. But maybe I should use `urldate` too. Let me add `urldate = {2026-09-17}` to the online entries. That's good practice.

Now, the README:

```markdown
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

## Other web-based renderers

- **TeXLive.net** — paste the `.tex` body into <https://texlive.net> for a quick one-off render (no account needed).
- **Papeeria** — free online LaTeX editor, similar workflow to Overleaf.

## Notes

- Citations use `natbib` with the `plainnat` style (author–year, e.g. `(Aaen, 2008)`).
- DOIs are rendered as clickable links via the `doi` package.
- All references from the markdown are included in `references.bib`; add new ones there and cite them with `\citep{key}`.
```

Hmm, TeXLive.net — actually the service is at https://texlive.net/run or https://latexonline.cc. Let me be careful about recommending services I'm not sure about. TeXLive.net does exist (run by the TeX Live team, renders LaTeX via URL). LaTeX.Online (latexonline.cc) also exists. Let me mention Overleaf primarily and keep alternatives brief and generic.

Actually, let me simplify: mention Overleaf as the main path, and note that any LaTeX distribution works locally. I'll keep the alternatives section short.

Now let me create the files. I'll create the directory implicitly via create_file (it creates directories automatically).

Let me finalize and create:
1. `c:\software\psc-elixir\docs\latex\project_proposal.tex`
2. `c:\software\psc-elixir\docs\latex\references.bib`
3. `c:\software\psc-elixir\docs\latex\README.md`

Let me write the final content for each.

For the .bib file, let me finalize with urldate on online entries.

Actually, one more check on the bib: `@misc{aaen2012essence}` — plainnat will render it as "Ivan Aaen. Essence: Team-Based Software Innovation. 2012." That's fine.

Also for `@inproceedings{roschnik2024approaching}` without publisher — plainnat renders "In ICIS Proceedings. 2024." Fine.

Let me also double check the `doi` package handles the `doi` field in `@inproceedings` and `@article` — yes, it hooks into the bibliography output for all entry types.

One concern: the `doi` package with `plainnat` — the doi package works by patching the bibliography. It should work. If there were issues, the user could remove `\usepackage{doi}`. I'll note in the README that DOIs are clickable.

Alright, let me also think — should I verify the LaTeX compiles? I can't easily compile LaTeX here (no LaTeX installed presumably, and it's Windows). I could check if there's a LaTeX toolchain... Actually, let me not attempt compilation; the document is standard and should compile fine. I'll carefully review the syntax.

Let me double-check a few LaTeX syntax details:
- `\citep{key1,key2}` — correct.
- `\href{url}{text}` — correct.
- `\paragraph{Title.}` — correct.
- `\bibliography{references}` — correct (references.bib).
- `\tableofcontents` — correct.
- Title page with `\begin{titlepage}` — correct.
- `\setlist{...}` from enumitem — correct.
- `\titleformat` from titlesec — correct.

One thing: `\usepackage[round]{natbib}` — the `round` option gives (Author, Year). Good.

Also, in the title page, `\\[0.4em]` inside `{\Huge\bfseries ...}` — the line break inside a group with font commands. `{\Huge\bfseries Developing a Configurable Platform for\\[0.4em] Collaborative Visual Inquiry Tools\par}` — this works.

Also `\vspace*{2cm}` at the top of titlepage — fine.

I think the document is solid. Let me create the files.

Actually, let me reconsider one more time whether to also provide a `main.tex` naming. Overleaf convention is often `main.tex`. But `project_proposal.tex` is descriptive. Overleaf doesn't care about the name. I'll keep `project_proposal.tex`.

Let me create the files now.

Also, I should give a brief summary to the user explaining what I created and how to use it, including the Overleaf steps. And per the user's teaching preference, I should explain the key decisions (natbib vs biblatex, why plainnat, etc.) briefly.

Let me create the three files in parallel.

</details>

I'll transform your project proposal into a LaTeX document ready for Overleaf. Let me create the main `.tex` file, a BibTeX bibliography, and a quick-start README.

> **🔧 ✓ Creating [](file:///c%3A/software/psc-elixir/docs/latex/project_proposal.tex)**

> *[Code edit applied]*

> **🔧 ✓ Creating [](file:///c%3A/software/psc-elixir/docs/latex/references.bib)**

> *[Code edit applied]*

> **🔧 ✓ Creating [](file:///c%3A/software/psc-elixir/docs/latex/README.md)**

> *[Code edit applied]*

<details>
<summary>💭 Thinking — Created project_proposal.tex, references.bib, and README.md</summary>

The files are created. Let me give a concise summary to the user explaining what I did and the key decisions, plus how to use it on Overleaf. Per the user's teaching preference, I should briefly explain the reasoning behind the choices.

</details>

Done! I created a complete LaTeX version of your proposal in `latex`:

| File | Purpose |
| --- | --- |
| `project_proposal.tex` | Main document — title page, TOC, all sections |
| `references.bib` | All 16 references as BibTeX entries |
| `README.md` | Overleaf + local compile instructions |

## Key decisions (and why)

- **`natbib` + `plainnat` (author–year)** instead of `biblatex` — this works with Overleaf's *default* settings (pdfLaTeX + BibTeX) with zero configuration. `biblatex` would require switching the compiler to Biber, an extra step you don't need.
- **Inline citations converted to `\citep{...}`** — e.g. `(Aaen, 2008; Aaen, 2012)` in the markdown became `\citep{aaen2008essence,aaen2012essence}`, so the bibliography is generated automatically and stays consistent with the text.
- **DOIs as clickable links** via the `doi` package — every reference with a DOI gets a working link.
- **Title page** with supervisor/student emails as `mailto:` links (I used the correct addresses, not the typos in the markdown's `mailto:` targets).
- **Cross-reference** — the Insights section now says "Section 4" via `\ref{sec:analytics}` instead of a hardcoded number.

## To render it

1. Go to [overleaf.com](https://www.overleaf.com) → **New Project → Blank Project**
2. Drag `project_proposal.tex` and `references.bib` into the file tree
3. Click **Recompile** — that's it (default pdfLaTeX + BibTeX settings work as-is)

If you'd rather render without an account, you can paste the `.tex` body into a service like [TeXLive.net](https://texlive.net) for a quick one-off PDF.

One note: I kept the bibliography entries faithful to what's in the markdown (author, title, year, DOI) without inventing volume/page numbers. If you have the full bibliographic details (e.g., volume, pages, publisher for Aaen 2012), you can add them to `references.bib` and they'll appear automatically.

---

