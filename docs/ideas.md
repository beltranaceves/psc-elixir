
# Ideas

## LLM-driven user proxies for interaction studies

- Summary: While the platform will provide a powerful analytics engine that records fine-grained interaction traces, we prefer to limit running large-scale human user studies early on. To explore large experimental conditions and to validate analytics pipelines, investigate using LLM-based agents as proxy users. Agents would be instantiated with preloaded user profiles and behavioral policies to simulate realistic editing, commenting, and navigation on canvases.

- Why: This approach lets us exercise telemetry pipelines, stress-test delta/versioning logic, and produce labeled interaction datasets for initial algorithm development without recruiting human subjects for every experiment.

- How (sketch):
	* Define a small language for user intents (e.g., create/move/edit cell, comment, group, rename), and profile templates describing frequency, latency, and preference distributions.
	* Preload agent profiles (persona, expertise level, typical session length) and use LLM prompts to generate action sequences consistent with profiles.
	* Execute generated sequences against instrumented canvases (CRDT-backed), capture exported traces, and compare to any available real-user traces to calibrate agents.

- Risks & mitigations:
	* Agents may not reflect real human strategies — mitigate by calibrating against small human pilot studies and iterating profiles.
	* Prompting LLMs for structured actions requires careful validation; add schema checks and replay tests.

- Next steps:
	* Prototype a single agent persona and one simple canvas scenario, generate and record 100 sessions, and inspect resulting traces for diversity and realism.

