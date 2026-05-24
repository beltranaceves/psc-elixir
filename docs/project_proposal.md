# Developing a Configurable Platform for Collaborative Visual Inquiry Tools: The Problem–Solution Canvas

Ivan Aaen: email [ivan@cs.aau.dk](mailto:ivan@cs.aau.dk)

# Project Summary

This project focuses on developing a web-based, configurable platform for creating and using Visual Inquiry Tools (VITs), with a particular emphasis on the Problem–Solution Canvas (PSC) Ivan Aaen. Visual inquiry tools are common in both practice and research: industry products such as Miro and MURAL, and a variety of canvas-style templates (e.g., the Business Model Canvas), support collaborative idea work. Our aim is not to replace those tools but to provide a platform that combines template configurability and real-time collaboration with structured, fine-grained capture of user interactions so that edits, sequences, and decisions can be analyzed after the fact.

The platform will therefore let users:

- define and share canvas templates (e.g., PSC variants),
- instantiate collaborative canvas instances that load and synchronize in real time, and
- record meaningful changes using a delta-based versioning model that links edits to decisions and pivots, producing exportable interaction traces and user-analytics-ready datasets for study.

Implemented as a web application using the Elixir/Phoenix stack, the platform will provide CRDT-based real-time collaboration (LiveView-powered front end and conflict-free merging on the server), persistent canvas instantiation and delta-based versioning that links edits to decisions and pivots, and a lightweight telemetry pipeline for capturing exportable interaction traces and aggregated metrics for later study. The immediate goal is a minimal, extensible MVP that demonstrates template configurability, synchronized collaborative editing, and meaningful delta capture; subsequent phases will scale the analytics, experiment tooling, and dataset exports for larger studies.

# Background

Visual Inquiry Tools (VITs) are structured visual frameworks used to support collaborative inquiry, problem framing, ideation, and decision-making. Common examples include canvases, maps, and collaborative diagrammatic workspaces that help teams externalize knowledge and iteratively refine understanding during innovation processes.

The Problem–Solution Canvas (PSC) is a Visual Inquiry Tool developed within the context of software and digital innovation research by Ivan Aaen and collaborators. Building on the *Essence* approach to software innovation, the PSC emphasizes iterative problem framing and the co-evolution of problems and solutions through collaborative inquiry, reinterpretation, and negotiation among team members.

Digital innovation problems are often ambiguous, evolving, and socio-technical, making them difficult to capture using static or linear planning tools. Existing industry platforms such as [Strategyzer](https://www.strategyzer.com), [Miro](https://miro.com), [MURAL](https://www.mural.co), [Canvanizer](https://canvanizer.com), [Lean Canvas](https://leanstack.com/leancanvas), and [IDEO Design Thinking Tools](https://www.designthinking.ideo.com/tools) provide reusable templates and collaborative workspaces, but generally offer limited support for analyzing how ideas evolve over time. Similarly, literature on canvas-based and inquiry-oriented tools includes the Business Model Canvas Business Model Generation, Lean Canvas Running Lean, Design Principle Canvas, and recent work on digital inquiry platforms and collaborative visual analytics. This project aims to address that gap by combining configurable visual inquiry templates, real-time collaboration, and fine-grained interaction tracing into a unified research-oriented platform.

 - Examples of existing tools in literature:

	- Business Model Canvas — Osterwalder, A., & Pigneur, Y. (2010). Business Model Generation.
	- Lean Canvas — Maurya, A. (2012). Running Lean.
	- Design Principle Canvas — Schoormann, T., et al. (2023). Guiding Design Principle Projects: A Canvas for Young Design Science Researchers.
	- Digital Inquiry Platform concepts — Roschnik, A., et al. (2024). Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform.
	- Collaborative visual inquiry and analytics research — Chen, L., et al. (2020). Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices.
	- Visual inquiry and contextual knowledge sharing — Sandberg, F. (2019). Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge.

 - Examples of existing tools in industry:

	- [Strategyzer](https://www.strategyzer.com/library?type=Tools)
	- [Miro](https://miro.com)
	- [MURAL](https://www.mural.co/templates)
	- [Canvanizer](https://canvanizer.com)
	- [Lean Canvas](https://leanstack.com/leancanvas)
	- [Design Thinking templates](https://www.designthinking.ideo.com/tools)
	- [Innovation tools in literature](https://www.sciencedirect.com/science/article/pii/S0160791X2100028X)

## Methods

The project will be executed in two main phases:
One

- Development of the main web application with VIT core features
- Implementation of the delta-based versioning exploration mechanism
- Implementation of the analytics engine to lay the foundation for experimentation.
	Two
- Design and execution of experiments using the analytics engine to capture user interactions and study patterns of use, problem framing, and solution development.

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

### 3. Delta Model & Change Visualization

Provide a delta model and visualization for meaningful changes:

- represent edits as deltas (pivots, decisions, reinterpretations),
- link deltas to versioning and allow timeline/step replay,
- provide tools to annotate and group deltas for analysis.

### 4. Analytics & Interaction Telemetry

Capture interaction traces to support later analysis and experiments:

- log order of interactions, frequency/distribution of edits, and metadata,
- expose exportable event streams and lightweight aggregation APIs,
- enable studies of user archetypes, framing patterns, and outcome correlations.

# Deliverables

- A working web application built with Elixir/Phoenix
- Support for:

	- configurable visual inquiry templates
	- collaborative canvas instances
	- delta-based versioning
- A basic analytics infrastructure capturing user interactions
- A written report describing:

	- design decisions
	- system architecture
	- and implications for supporting visual inquiry and innovation

# Key References

## Core Concepts

Ivan Aaen (2008). *Essence: Facilitating Software Innovation.* European Journal of Information Systems.

Ivan Aaen (2012). *Essence: Team-Based Software Innovation.*

Alexander Osterwalder, & Yves Pigneur (2010). *Business Model Generation.*

## Visual Inquiry Tools and Collaborative Inquiry

Sandberg, F. (2019). *Visual Inquiry: A Tool for Presenting and Sharing Contextual Knowledge.*

Schoormann, T., Möller, F., Di Maria, M., & Große, N. (2023). *Guiding Design Principle Projects: A Canvas for Young Design Science Researchers.* Journal of Information Systems Education.

Roschnik, A., Jaccard, D., Monnier, S., & Missonier, S. (2024). *Approaching Visual Inquiry Tools through the Lens of Systems Thinking: The Proposal of a Digital Inquiry Platform.* ICIS Proceedings.

## Collaboration, Visual Analytics, and Interaction Analysis

Kolloffel, B., Eysink, T. H. S., & de Jong, T. (2011). *Comparing the Effects of Representational Tools in Collaborative and Individual Inquiry Learning.* International Journal of Computer-Supported Collaborative Learning.

Chen, L., Liang, H.-N., Lu, F., Papangelis, K., Man, K. L., & Yue, Y. (2020). *Collaborative Behavior, Performance and Engagement with Visual Analytics Tasks Using Mobile Devices.* Human-centric Computing and Information Sciences.

Chen, L., Liang, H.-N., Wang, J., Qu, Y., & Yue, Y. (2021). *On the Use of Large Interactive Displays to Support Collaborative Engagement and Visual Exploratory Tasks.* Sensors.

A systematic review of visual representations for analyzing collaborative discourse. *Educational Research Review* (2021).
