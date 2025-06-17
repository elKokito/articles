Below is a drop-in **Markdown file** that includes a miniature example for every diagram grammar listed in the Mermaid v11 syntax reference. Save it as `mermaid-showcase.md` (or any name you like), give it a YAML front-matter block so Jekyll treats it as a page, and—provided your site template loads the `mermaid.min.js` script or you let GitHub render the blocks in-place—you’ll get a live catalogue of all diagram types on your GitHub Pages site.([docs.github.com][1], [mermaid.js.org][2], [mermaid.js.org][3], [mermaid.js.org][4], [mermaid.js.org][5], [mermaid.js.org][6], [mermaid.js.org][7], [mermaid.js.org][8], [mermaid.js.org][9], [mermaid.js.org][10])

> **Tip for Pages:** add
>
> ```html
> <script type="module">
>   import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
>   mermaid.initialize({ startOnLoad: true });
> </script>
> ```
>
> in your layout (or `_includes/head.html`) to ensure every diagram renders during page load.([mermaid.js.org][10])

---

````markdown
---
layout: default          # adapt to your theme
title: Mermaid Diagram Showcase
description: Live examples of every diagram grammar supported by Mermaid v11
---

## Core diagrams

### Flowchart
```mermaid
flowchart TD
  A[Start] --> B{Is it?}
  B -->|Yes| C[OK]
  B -->|No| D[Not OK]
````

### Sequence diagram

```mermaid
sequenceDiagram
  participant Alice
  participant Bob
  Alice->>Bob: Hello Bob!
  Bob-->>Alice: Hi Alice!
```

### Class diagram

```mermaid
classDiagram
  class Animal {
    +String name
    +int age
    +eat()
  }
  Animal <|-- Dog
```

### State diagram

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Busy : event
  Busy --> Idle : reset
```

### Entity-Relationship (ER) diagram

```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER     ||--|{ LINE_ITEM : contains
```

### Gantt chart

```mermaid
gantt
  title Project Schedule
  dateFormat  YYYY-MM-DD
  section Milestones
  Spec complete :done,    2025-06-01, 1d
  Build         :active,  2025-06-02, 5d
```

### Pie chart

```mermaid
pie title Pet popularity
  "Cats" : 45
  "Dogs" : 55
```

### Journey (user-journey) diagram

```mermaid
journey
  title Checkout experience
  section Browse
    Choose products    : 5: user
  section Payment
    Enter card details : 3: user
    Confirm order      : 1: user
```

## Project & planning diagrams

### Quadrant chart

```mermaid
quadrantChart
  title Value vs Effort
  x-axis Effort ["Low", "High"]
  y-axis Value  ["Low", "High"]
  "Quick Win": [0.2,0.8]
  "Big Bet"  : [0.8,0.9]
```

### Requirement diagram

```mermaid
requirementDiagram
  requirement req1 {
    id: 1
    text: System shall be reliable
    risk: high
  }
```

### Kanban board

```mermaid
kanban
  title Sprint Board
  column Backlog
    Task A
  column In-Progress
    Task B
  column Done
    Task C
```

### Git graph

```mermaid
gitGraph
  commit
  branch feature
  commit
  checkout main
  merge feature
```

## C4 architecture set

### C4 Context

```mermaid
C4Context
  Person(admin, "Admin")
  System(system, "Web App")
  Rel(admin, system, "Uses")
```

### C4 Container

```mermaid
C4Container
  Container(web, "Web UI", "React")
  ContainerDb(db, "PostgreSQL")
  Rel(web, db, "Reads/Writes")
```

### C4 Component

```mermaid
C4Component
  Component(service, "Auth Service", "Go")
  Component(cache, "Redis Cache", "Redis")
  Rel(service, cache, "Stores sessions")
```

### C4 Deployment

```mermaid
C4Deployment
  Deployment_Node(k8s, "Kubernetes") {
    Container(web)
  }
```

## Data-flow & visual-thinking diagrams

### Mind-map *(experimental)*

```mermaid
mindmap
  root((Mermaid))
    Use-cases
      Docs
      Slides
    Integrations
      GitHub
      GitLab
```

### Timeline

```mermaid
timeline
  title Release timeline
  2024-01-01 : v1.0 released
  2025-06-01 : v2.0 released
```

### Sankey *(experimental)*

```mermaid
sankey
  style spacing 64
  A[Input]  -> B[Process] : 10
  B         -> C[Output]  : 10
```

### XY chart *(beta)*

```mermaid
xychart-beta
  title "Monthly sales"
  x-axis [Jan, Feb, Mar]
  y-axis "USD" 0 --> 100
  bar  [30, 70, 50]
  line [20, 80, 60]
```

### Radar *(experimental)*

```mermaid
radar
  title Team skills
  axes
    Coding
    Design
    Testing
  data
    Alice : [4,3,5]
    Bob   : [5,4,4]
```

### Block diagram

```mermaid
block
  CPU --> Memory
  Memory --> Disk
```

### Packet diagram

```mermaid
packet
  { IPv4 Header : 20B }
  { Payload     :  N  }
```

### Architecture diagram *(experimental)*

```mermaid
architecture
  layer Presentation
  layer Domain
  layer Data
  Presentation --> Domain --> Data
```

### ZenUML (sequence-style)

```mermaid
zenuml
  A -> B: Request
  B --> A: Response
```

---

Copy this file into your repository, make sure Mermaid is being initialised on the page, and you’ll have a living gallery that demonstrates every grammar currently documented in Mermaid v11.

[1]: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams?utm_source=chatgpt.com "Creating diagrams - GitHub Docs"
[2]: https://mermaid.js.org/intro/syntax-reference.html "Diagram Syntax | Mermaid"
[3]: https://mermaid.js.org/syntax/flowchart.html?utm_source=chatgpt.com "Flowcharts Syntax | Mermaid - JS.ORG"
[4]: https://mermaid.js.org/syntax/pie.html?utm_source=chatgpt.com "Pie chart diagrams | Mermaid - JS.ORG"
[5]: https://mermaid.js.org/syntax/sequenceDiagram?utm_source=chatgpt.com "Sequence diagrams | Mermaid - JS.ORG"
[6]: https://mermaid.js.org/syntax/c4.html?utm_source=chatgpt.com "C4 Diagrams | Mermaid - JS.ORG"
[7]: https://mermaid.js.org/syntax/xyChart.html?utm_source=chatgpt.com "XY Chart | Mermaid - JS.ORG"
[8]: https://mermaid.js.org/syntax/mindmap.html?utm_source=chatgpt.com "Mindmap | Mermaid - JS.ORG"
[9]: https://mermaid.js.org/config/schema-docs/config-defs-pie-diagram-config.html?utm_source=chatgpt.com "Pie Diagram Config Schema | Mermaid - JS.ORG"
[10]: https://mermaid.js.org/intro/getting-started.html?utm_source=chatgpt.com "Mermaid User Guide | Mermaid - JS.ORG"

