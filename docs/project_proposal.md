# Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem–Solution Canvas

9th Semester

Supervisor: Ivan Aaen - [ivan@cs.aau.dk](mailto:ivan@cs.af)
Student: Beltran Aceves - [baceve25@student.aau.dk](mailto:baceve25@stduent.aau.dk)


# Project Summary

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs) collaboratively, with a particular emphasis on the Problem-Solution Canvas (PSC); developed by Ivan Aaen. Visual inquiry tools are common in both industry and research: commercial products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas, Lean Canvas). Our aim is not to replace those tools, but to provide a platform that combines configurability and observability for the purpose of studying user interactions within these systems

The platform will therefore let users:

- define and share canvas templates (e.g., PSC variants)
- instantiate collaborative canvas instances that load and synchronize in real time
- explicitly version canvas progress via a delta-based, tree-like model which records the reason for pivoting, that supports visualizing and traversing versions
- automatically capture user interaction events and metrics via an analytics engine for later study, producing exportable event streams datasets,
- analyze canvas content via an insights system that surfaces coherence, staleness, and quality signals (e.g., cells deviating from the central theme, old/stale cells), using LLMs among other methods.

Implemented as a web application using the Elixir/Phoenix/Postgres stack, the platform will provide CRDT-based real-time collaboration, a canvas template configurator, a versioning system, a process for capturing user interactions, and an insights system for analyzing canvas contents.

The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, explicit version capture, automatic interaction capture, and content-level insights; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.

# Background

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem–Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the *Essence* approach to software innovation (Aaen, 2008; Aaen, 2012), the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as [Strategyzer](https://www.strategyzer.com), [Miro](https://miro.com), [MURAL](https://www.mural.co), [Canvanizer](https://canvanizer.com), [Lean Canvas](https://leanspark.ai/leancanvas), and [IDEO Design Thinking Tools](https://designthinking.ideo.com/) provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time or whether canvas content remains coherent and up to date. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas (Osterwalder & Pigneur, 2010), Lean Canvas (Maurya, 2012), Design Principle Canvas (Schoormann et al., 2023), and recent work on digital inquiry platforms (Roschnik et al., 2024; Avdiji et al., 2020) and collaborative visual analytics (Chen et al., 2020; Chen et al., 2021; Kolloffel et al., 2011; Hu & Chen, 2021), as well as visual inquiry for sharing contextual knowledge (Sandberg, 2011). This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, fine-grained interaction tracing, and content-level insights into a unified research-oriented platform.

 - Examples of existing tools in literature:

	- Business Model Canvas — Osterwalder, A., & Pigneur, Y. (2010). Business Model Generation.
	- Lean Canvas — Maurya, A. (2012). Running Lean.
	- Design Principle Canvas — Schoormann, T., et al. (2023). Guiding Design Principle Projects: A Canvas for Young Design Science Researchers.
	- Digital Inquiry Platform concepts — Roschnik, A., et al. (2024). Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform. See also Avdiji et al. (2020).
	- Collaborative visual inquiry and analytics research — Chen, L., et al. (2020). Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices. See also Chen et al. (2021); Kolloffel et al. (2011); Hu & Chen (2021).
	- Visual inquiry and contextual knowledge sharing — Sandberg, F. (2011). Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge.

 - Examples of existing tools in industry:

	- [Strategyzer](https://www.strategyzer.com/library?type=Tools)
	- [Miro](https://miro.com)
	- [MURAL](https://www.mural.co/templates)
	- [Canvanizer](https://canvanizer.com)
	- [Lean Canvas](https://leanspark.ai/leancanvas)
	- [Design Thinking tools (IDEO U)](https://designthinking.ideo.com/)

## Project Goals

The project focuses on building the MVP:

- Development of the main web application with VIT core features
- Implementation of the delta-based versioning system: explicit milestones/versions/commits in a traversable tree, with visualization and recorded pivot/bifurcation rationale
- Implementation of the insights system for analyzing canvas content (coherence, staleness, quality signals, with optional LLM-enabled insights)
- Implementation of the analytics engine (automatic capture of interaction events and metrics) to lay the foundation for later study.

## Functional Requirements

### 1. Core Tooling for VITs

Design and implement core tooling for building Visual Inquiry Tools (VITs). This includes:

- defining canvas structure (cells, relations, semantics) and templates,
- editor UI and components for creating and editing cells,
- template persistence and instantiation of canvases.

### 2. Collaborative Workspaces

Develop workspaces for real-time collaboration on canvases. This includes:

- real-time collaborative editing using CRDTs with live document loading and conflict-free merges,
- per-user presence and cursor indicators, plus inline comments and discussion threads,
- sharing, access control, and session management for team sessions.

Presence, awareness, and representational guidance follow findings on collaborative inquiry learning and engagement with shared visual tasks (Kolloffel et al., 2011; Chen et al., 2020; Chen et al., 2021).

### 3. Delta Model & Versioning

A PSC, or any other VIT instance,  evolves continuously during collaborative real-time sessions. This fluid evolution is normal and expected, but teams also need to explicitly mark that they have reached a meaningful point in the progress of their project or canvas.

The delta system provides this intentional versioning layer, to:

- let users create explicit milestones/versions/commits (snapshots) of the canvas at chosen moments;
- organize versions in a tree-like manner supporting linear history as well as branches for pivots, bifurcations, and parallel alternatives;
- visualize and traverse the version tree (timeline/tree view, diff/compare between versions, restore or fork from any version);
- record the reason for each pivot or bifurcation (decision rationale, reinterpretation note, author, timestamp, parent link(s));
- provide tools to annotate and group deltas/versions for later analysis.


### 4. Analytics & Interaction Telemetry

The platform provides an analytics engine that automatically captures all kinds of events and metrics from users interacting with the system, so they can be analyzed later:

- passively log interaction events (edits, navigation, presence, comments, version operations, insight views) with order, frequency/distribution, and metadata (who, when, where in the canvas, session/device context);
- expose exportable event streams and lightweight aggregation APIs for research use;
- enable studies of user archetypes, framing patterns, collaboration dynamics, and outcome correlations.

Event models and visual representations for collaborative discourse build on prior work in visual analytics and discourse analysis (Chen et al., 2020; Chen et al., 2021; Hu & Chen, 2021).

### 5. Insights & Content Analysis

Analyze the contents of a given PSC to support reflection and convergence, complementing the interaction-level analytics in section 4:

- detect cells deviating from the central theme or problem framing of the canvas,
- detect old/stale cells (e.g., untouched, superseded, or inconsistent with recent pivots/decisions),
- surface coherence and quality signals (e.g., contradictions, gaps, duplicates across cells),
- provide LLM-enabled insights where appropriate (e.g., summaries, suggestions, theme-drift explanations), designed as an optional, pluggable layer over deterministic heuristics so the platform remains usable without an LLM provider.

Content-level coherence builds on design theory for visual inquiry tools (Avdiji et al., 2020) and canvas-based guidance for design projects (Schoormann et al., 2023).


## Non-Functional Requirements
- The platform should be built using the Elixir/Phoenix stack for scalability and real-time capabilities.
- The system should be designed for extensibility to support future features and different types of VIT, including new insight detectors and LLM providers
- The user interface should be intuitive and responsive to facilitate collaboration and ease of use, including support for both desktop and mobile devices.
- The platform should ensure data integrity and consistency during real-time collaboration, using CRDTs for conflict-free merging of changes.
- The analytics infrastructure should be designed to efficiently capture and store interaction data while minimizing performance overhead on the user experience.
- The insights system should run efficiently alongside editing (e.g., asynchronous/on-demand analysis) and keep LLM usage optional, privacy-aware, and clearly attributed, so canvases remain fully usable without external AI services.
- The system should be easy to deploy and maintain, with clear documentation for both users and developers.

# Deliverables

- A working web application built with Elixir/Phoenix
- Project documentation and deployment guide
- Support for:
	- configurable visual inquiry templates
	- collaborative canvas instances
	- delta-based pivot versioning
	- insights system for canvas content analysis (theme deviation, stale cells, coherence signals, with optional LLM-enabled insights)
	- A basic analytics engine automatically capturing user interaction events and metrics, with exportable streams for later analysis
- A written report describing:
	- design decisions
	- system architecture
	- and implications for supporting visual inquiry and innovation

# Future Work

The following are out of scope for the MVP but are natural next steps once the core platform is in place.

- **Experiments on user behavior.** Design and run studies using the analytics engine to look at patterns of use, problem framing, and solution development; such as user archetypes, framing patterns, collaboration dynamics, and how they relate to outcomes. This would also mean scaling up the analytics side: experiment tooling, aggregation APIs, and dataset exports for larger studies.

- **Non-table canvases.** The MVP assumes table-like canvases made of cells. Later we want templates that are not grids at all: a background image or SVG with floating text inputs placed on top of it. This would support more visual or spatial VITs (maps, diagrams, annotated pictures) using the same collaboration, versioning, and analytics foundations.

# References

## Frameworks and Libraries
- Elixir: https://elixir-lang.org
- Phoenix: https://www.phoenixframework.org
- Delta CRDTs: https://github.com/derekkraan/delta_crdt_ex
- LiveView: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView

## Core Concepts

Ivan Aaen (2008). *Essence: Facilitating Software Innovation.* European Journal of Information Systems. https://doi.org/10.1057/ejis.2008.43

Ivan Aaen (2012). *Essence: Team-Based Software Innovation.*

Alexander Osterwalder, & Yves Pigneur (2010). *Business Model Generation.* https://www.strategyzer.com/books/business-model-generation

Ash Maurya (2012). *Running Lean.* https://leanspark.ai/leancanvas

## Visual Inquiry Tools and Collaborative Inquiry

Sandberg, F. (2011). *Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge.* Nordic Design Research Conference. https://doi.org/10.21606/nordes.2011.028

Schoormann, T., Möller, F., Di Maria, M., & Große, N. (2023). *Guiding Design Principle Projects: A Canvas for Young Design Science Researchers.* Journal of Information Systems Education. https://doi.org/10.62273/wkbc7575

Roschnik, A., Jaccard, D., Monnier, S., & Missonier, S. (2024). *Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform.* ICIS Proceedings.

Avdiji, H., Elikan, D., Missonier, S., & Pigneur, Y. (2020). *A Design Theory for Visual Inquiry Tools.* Journal of the Association for Information Systems. https://doi.org/10.17705/1jais.00617

## Collaboration, Visual Analytics, and Interaction Analysis

Kolloffel, B., Eysink, T. H. S., & de Jong, T. (2011). *Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning.* International Journal of Computer-Supported Collaborative Learning. https://doi.org/10.1007/s11412-011-9110-3

Chen, L., Liang, H.-N., Lu, F., Papangelis, K., Man, K. L., & Yue, Y. (2020). *Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices.* Human-centric Computing and Information Sciences. https://doi.org/10.1186/s13673-020-00253-7

Chen, L., Liang, H.-N., Wang, J., Qu, Y., & Yue, Y. (2021). *On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks.* Sensors. https://doi.org/10.3390/s21248403

Hu, L., & Chen, G. (2021). *A Systematic Review of Visual Representations for Analyzing Collaborative Discourse.* Educational Research Review. https://doi.org/10.1016/j.edurev.2021.100403
