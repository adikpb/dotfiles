# Competitive Landscape Gap Analysis

## When to use this reference

Use during **Phase 2 (Research the reality)** when the idea sits in a crowded space (developer tools, consumer apps, content formats, AI products) and you need to find a differentiated wedge. This methodology is for **creative ideation** — finding untapped territory — not for market-sizing or business-model validation.

## Method summary

1. Gather the landscape → 2. Categorize by pattern → 3. Assess saturation → 4. Identify gaps → 5. Generate from gaps

---

## Step 1: Gather the landscape

Search broadly across the domain. Use multiple query angles:

```
web_search("funny AI coding tools")
web_search("parody CLI developer tools")
web_search("humorous open source terminal projects")
web_search("satirical AI assistant projects")
```

Also check:

- GitHub topic tags (`topic:fun`, `topic:humor`, `topic:parody`, `topic:cli`)
- npm/crates.io/pypi for joke packages
- Product Hunt / Hacker News Show archives for similar launches

Collect at least 8-15 entries. Record: name, one-line what-it-does, repo URL.

---

## Step 2: Categorize by pattern

Group projects by **comedy mechanism** — how does the joke work? Common patterns in developer tools:

| Pattern | Definition | Example |
|---------|------------|---------|
| **Personality overlay** | Wraps an existing tool in a character voice | Moxie (14 personalities), Gen-Z Claude Bro |
| **Roasting** | Insults user's code or output | RoastCLI, git-roast, Nopilot |
| **Pretend-to-work** | Fake productivity theater | rust-stakeholder, bewupdate, potemkin-pipeline |
| **Refusal** | Actively refuses to help | Nopus (100% refusal) |
| **Adversarial** | Two+ perspectives arguing | Dinesh-Gilfoyle /dg |
| **Companion** | Virtual pet / care mechanics | goodboy (Tamagotchi dog) |
| **Systems-change** | Changes how the tool works (economy, gacha, time-based) | *(gap — few examples)* |
| **Fake utility** | Parody replacement for real tools | coretilus, sicktiergit |
| **Shitpost generator** | Creates social-media/chat content | shitpost-reactor |

For non-developer domains (market research, content strategy, product ideas), create categories specific to that domain's comedy or differentiation patterns.

---

## Step 3: Assess saturation

For each category, ask:

- **How many projects exist in this pattern?** (count)
- **Is there a clear "best in class"?** (quality bar)
- **Is the pattern broad enough for multiple entrants?** or is it a one-joke lane?
- **Is a new entrant competing on quality or angle?** (don't compete on quality against an established leader)

Mark each category:
- **Saturated** — too many entrants, or one dominant player. Avoid.
- **Doable** — some entrants, but room for a different angle.
- **Green field** — no shipped example found. Strong signal for novelty.

---

## Step 4: Identify gaps

Look at saturated categories and ask: **what's the inverse?**

- If everyone roasts (negative) → what about a tool that's overly supportive?
- If everyone adds personality (character overlay) → what about a tool that changes *rules* (systems)?
- If tools are helpful → what about adversarial or refusal?
- If tools are deterministic → what about RNG/gacha mechanics?
- If tools are static → what about time-based behavior changes?

Also look at **cross-category mashups** nobody has tried:
- Personality + systems (a character that also changes rules)
- Time-based + personality (character that degrades)
- Economy + refusal (paid snark)

---

## Step 5: Generate from gaps

For each gap found, generate 2-3 concrete concepts that fill it. Each concept should have:

- A **mechanism** (how the joke works mechanically, not just dialogue)
- A **staying-power assessment** (does it survive 10+ sessions?)
- A **feasibility note** (what API surface or platform hooks it needs)

Test concepts against the gap: "If this ships, would it be the first thing in this category, or competing with something established?"

---

## Worked example: Pi meme package

From the session that produced this reference:

**Domain:** Funny AI coding agent extensions
**Gathered:** 15+ projects (Moxie, Nopus, goodboy, RoastCLI, git-roast, Nopilot, /dg, potemkin-pipeline, coretilus, sicktiergit, shitpost-reactor, rust-stakeholder, bewupdate, bullshit-cli, gen-z-claude-bro)

**Categories found:**
- Roasting (4+ projects) → **Saturated**
- Personality overlay (2+, Moxie is dominant) → **Saturated**
- Pretend-to-work (3+) → **Doable but one-note**
- Refusal (1, Nopus is definitive) → **Saturated by one player**
- Fake utility (2+) → **Doable but short shelf life**
- Companion/pet (1, goodboy) → **Doable but lane is "wholesome"**
- **Systems-change (economy, gacha, time-based)** → **Green field**
- **Adversarial (2-agent)** → **Green field (only /dg exists)**

**Gaps found:**
- Gacha/lootbox tool access (untapped)
- Bureaucracy/economy systems (untapped)
- Time-based personality degradation (untapped)
- Fourth-wall-breaking / meta (untapped)

**Concepts generated from gaps:**
- Lucky Pi (gacha tool access) → green field
- Pi-Corp (bureaucracy) → green field
- Night Shift Pi (time-degradation) → green field

---

## Pitfalls

1. **"No direct competitor" ≠ good idea.** Check adjacent space, substitutes, and WHY nobody competes there (hard tech? niche audience? not funny?).
2. **Saturation doesn't mean "don't enter."** It means "have a clear differentiation thesis before entering."
3. **Green field can mean undiscovered, or it can mean unworkable.** Validate with a cheap prototype.
4. **Don't confuse project count with saturation.** One project may own a category (Nopus owns refusal). Multiple projects may indicate low barriers, not high demand.
