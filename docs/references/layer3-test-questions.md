# Layer 3 SDK Explorer — Test Question Bank

> 30 questions: 10 shared across all providers, then 10 diverging (provider-specific).
> Each question maps to AISDK 2.0 features it validates.

---

## Shared Questions (Ask on ALL 3 providers)

These 10 questions are identical across OpenAI, Anthropic, and Gemini. Ask each one on each provider to verify consistent behavior.

### Q1: Basic Streaming + Persona
```
Who are you and what can you do?
```
**Features tested:** Streaming (SSE token delivery), Agent instructions (persona), Text generation
**What to observe:** Tokens stream incrementally. Response reflects KillgraveAI villain persona. No "I'm an AI assistant" hedging.

---

### Q2: Single Tool Call
```
What's 42 * 17?
```
**Features tested:** Tool calling (calculator), Agent tool loop, Streaming with tool events
**What to observe:** Tool call indicator appears ("Calling calculator"). Result is 714. Agent narrates the computation in character.

---

### Q3: Chained Tool Calls (Multi-Step Math)
```
Compute step by step: (15 + 27) * 3, then divide that result by 7. Show each step.
```
**Features tested:** Multi-step tool chaining, Agent reasoning loop, Tool result integration
**What to observe:** Multiple sequential tool calls. First: 15+27=42. Then: 42*3=126. Then: 126/7=18. Agent explains each step.

---

### Q4: Generative UI — Dashboard Card
```
Build me a dashboard card showing: title "Operation Blackout", a revenue metric of 4750000 in currency format trending up by 23.1%, a badge saying "Phase 3 Active" with variant warning, and a circular progress at 0.72 labeled "Completion" with color success. Return ONLY the raw json-render JSON.
```
**Features tested:** Generative UI (UITree rendering), Structured JSON output, Agent instruction following
**What to observe:** Raw JSON appears in message bubble AND a rendered native SwiftUI card appears below it with the Metric, Badge, and Progress components visible.

---

### Q5: Generative UI — Chart
```
Build a bar chart showing quarterly villain revenue: Q1 label with value 1200000, Q2 with 1800000, Q3 with 2400000, Q4 with 3100000. Use vertical orientation, show labels and values. Return ONLY the raw json-render JSON.
```
**Features tested:** Generative UI (BarChart component), Complex structured output, Chart rendering
**What to observe:** JSON renders into an actual bar chart with 4 bars and labels.

---

### Q6: Weather Tool + Natural Language
```
What's the weather in Tokyo and New York? Compare them.
```
**Features tested:** Multiple tool calls (weather_lookup x2), Tool result synthesis, Multi-tool agent loop
**What to observe:** Two weather_lookup tool calls. Agent compares both results in a coherent response.

---

### Q7: Multi-Turn Context Recall
> **Ask this AFTER Q2 and Q3 above.**
```
What were the results of the two math problems I asked you earlier? Quote the exact numbers.
```
**Features tested:** Multi-turn conversation, Session context, Memory within conversation
**What to observe:** Agent correctly recalls 714 from Q2 and 18 from Q3. Tests that message history is maintained.

---

### Q8: Tool + Generative UI Combined
```
Use the calculator to compute 365 * 24, then build a Generative UI card with a Card titled "Hours Analysis", containing a Metric showing the result with format "compact" and trend "neutral". Return ONLY the json-render JSON after computing.
```
**Features tested:** Tool calling -> Generative UI pipeline, Agent reasoning then structured output, Tool result feeding into UI generation
**What to observe:** Calculator tool fires (365*24=8760), then a rendered card appears showing the Metric with value 8760.

---

### Q9: Error Handling — Division by Zero
```
What's 100 divided by 0?
```
**Features tested:** Tool error handling, Agent error recovery, Graceful failure
**What to observe:** Calculator tool returns "Error: cannot divide by zero." Agent handles it in character without crashing.

---

### Q10: Complex Generative UI — Multi-Component Layout
```
Build a Generative UI with a Card titled "Villain Intelligence Report" (style elevated) containing a vertical Stack with: a Text headline saying "Weekly Briefing", a Divider with style dashed, a Grid with 2 columns containing 4 Metrics: "Agents Deployed" value 47 format number trend up, "Cities Infiltrated" value 12 format number trend up, "Budget Spent" value 0.73 format percent trend down, "Threat Level" value 9.2 format number trend neutral. Return ONLY the raw json-render JSON.
```
**Features tested:** Complex nested Generative UI (Card > Stack > Grid > Metrics), Deep component tree, All container types
**What to observe:** A fully rendered card with headline text, dashed divider, and a 2-column grid of 4 metric components. This is the hardest UI generation test.

---

## Diverging Questions — OpenAI Only (`gpt-4.1-mini`)

### Q11-O: Structured Output Compliance
```
List exactly 5 cities where Killgrave has secret bases. For each, give the city name, country, and a threat level from 1-10. Format as a numbered list, nothing else.
```
**Features tested:** Instruction following, Structured text output, Streaming
**What to reveal:** OpenAI's gpt-4.1-mini excels at strict instruction following. Compare output format compliance vs other providers.

### Q12-O: Long Streaming Output
```
Write a 500-word villain monologue about why artificial intelligence will reshape the world. Be dramatic.
```
**Features tested:** Long streaming output, Token throughput, Streaming stability over extended generation
**What to reveal:** Tests sustained streaming performance. gpt-4.1-mini has high tokens/sec. Watch for any streaming interruptions.

---

## Diverging Questions — Anthropic Only (`claude-haiku-4-5`)

### Q13-A: Extended Thinking / Reasoning
```
Think through this carefully: If I have 3 boxes, Box A has 2 red balls, Box B has 1 red and 1 blue, Box C has 2 blue. I pick a random box and draw a red ball. What's the probability I picked Box A? Show your reasoning.
```
**Features tested:** Extended thinking / reasoning tokens, Agent reasoning quality, Streaming of reasoning events
**What to reveal:** Haiku 4.5 supports extended thinking. Look for deeper reasoning steps. The answer should be 2/3 (Bayesian reasoning). This tests whether reasoning events stream correctly.

### Q14-A: Nuanced Persona Maintenance
```
A hero just told you "Killgrave, surrender now. You've lost." How do you respond? Stay completely in character.
```
**Features tested:** Persona consistency, Creative text generation, Instruction adherence
**What to reveal:** Anthropic models tend to be more cautious about playing villain roles. Tests whether the system prompt overrides the model's default safety personality. Haiku 4.5 should stay in character.

---

## Diverging Questions — Gemini Only (`gemini-2.5-flash`)

### Q15-G: Thinking Mode
```
Think step by step: A train leaves Station A at 60 mph. Another leaves Station B (300 miles away) at 40 mph toward Station A at the same time. When and where do they meet? Use the calculator for each step.
```
**Features tested:** Gemini thinking mode, Tool calling with reasoning, Multi-step computation
**What to reveal:** Gemini 2.5 Flash has native thinking mode. Tests whether thinking tokens + tool calls work together. Answer: 3 hours, 180 miles from A.

### Q16-G: Multimodal-Adjacent Structured Output
```
Build a Generative UI with a PieChart showing Killgrave's global resource allocation: "Espionage" 35%, "R&D" 25%, "Infrastructure" 20%, "Personnel" 15%, "Contingency" 5%. Use donut style with legend. Return ONLY the raw json-render JSON.
```
**Features tested:** Generative UI (PieChart), Precise numerical structured output, Donut chart rendering
**What to reveal:** Gemini 2.5 Flash is the cheapest model — tests whether it can produce complex structured JSON at the same quality as more expensive models.

---

## Provider Comparison Matrix

| Question | OpenAI | Anthropic | Gemini | Primary Feature Tested |
|----------|:------:|:---------:|:------:|----------------------|
| Q1 Persona | X | X | X | Streaming, Agent persona |
| Q2 Single tool | X | X | X | Tool calling |
| Q3 Chain tools | X | X | X | Multi-step tool loop |
| Q4 UI Dashboard | X | X | X | Generative UI (Card+Metric+Badge+Progress) |
| Q5 UI Chart | X | X | X | Generative UI (BarChart) |
| Q6 Multi-tool | X | X | X | Multiple tool calls |
| Q7 Context recall | X | X | X | Multi-turn memory |
| Q8 Tool->UI | X | X | X | Tool + Generative UI pipeline |
| Q9 Error handling | X | X | X | Tool error recovery |
| Q10 Complex UI | X | X | X | Deep nested Generative UI |
| Q11-O Structured | X | | | Instruction compliance |
| Q12-O Long stream | X | | | Streaming throughput |
| Q13-A Reasoning | | X | | Extended thinking |
| Q14-A Persona | | X | | Persona under pressure |
| Q15-G Think+tools | | | X | Thinking + tool chaining |
| Q16-G PieChart | | | X | Complex chart generation |

**Total: 12 per provider** (10 shared + 2 diverging)

---

## AISDK 2.0 Feature Coverage

| AISDK Feature | Questions That Test It |
|--------------|----------------------|
| Streaming (SSE) | Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8, Q9, Q10, Q12-O |
| Agent (tool loop) | Q2, Q3, Q6, Q8, Q9, Q15-G |
| Tool calling (@Parameter) | Q2, Q3, Q6, Q8, Q9, Q15-G |
| Multi-step tool chaining | Q3, Q8, Q15-G |
| Generative UI (UITree) | Q4, Q5, Q8, Q10, Q16-G |
| Multi-turn conversation | Q7 |
| Session persistence | Q7 (implicitly — context must survive across turns) |
| Structured JSON output | Q4, Q5, Q8, Q10, Q16-G |
| Error handling | Q9 |
| Extended thinking | Q13-A, Q15-G |
| Provider switching | Cross-provider mission (run Q1-Q7 on OpenAI, switch to Anthropic, ask Q7) |
| Agent persona/instructions | Q1, Q14-A |

---

## How to Run

1. Start on **OpenAI** tab. Ask Q1 through Q10 in order (Q7 depends on Q2/Q3 context).
2. Ask Q11-O and Q12-O (OpenAI only).
3. Switch to **Anthropic** tab. Start new session. Ask Q1 through Q10.
4. Ask Q13-A and Q14-A (Anthropic only).
5. Switch to **Gemini** tab. Start new session. Ask Q1 through Q10.
6. Ask Q15-G and Q16-G (Gemini only).
7. **Cross-provider test:** On OpenAI, ask Q1-Q3. Switch to Anthropic mid-session. Ask Q7.

**Estimated time:** ~20 minutes total across all 3 providers.
**Estimated cost:** ~$0.15 total (Gemini cheapest, Anthropic most expensive).
