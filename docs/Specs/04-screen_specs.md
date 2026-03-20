# screen specs

## screen: app settings

### goal
Make advanced settings feel easy to scan and safe to change.

### layout
- split view
- left sidebar: categories
- right panel: detail content
- detail content width should not become too wide
- use vertical scrolling in detail panel

### sections
1. general
2. appearance
3. behavior
4. data
5. advanced
6. about

### right panel structure
For each category:
- page title
- short intro sentence if useful
- grouped cards
- destructive area at bottom if relevant

### spacing rhythm
- page outer padding: 24
- space between sections: 24 to 32
- card internal padding: 16
- row spacing inside cards: 12
- title to subtitle: 4 to 8
- section header to card: 12

### visual rules
- use background layering, not strong outlines
- selected sidebar item should feel integrated
- avoid floating random elements
- all columns should line up visually
- avoid overfilling horizontal space

### interaction rules
- immediate feedback for toggles
- dangerous actions require friction
- helper text should appear near relevant controls
- disabled states must remain readable

### implementation notes
- break each section into reusable SwiftUI views
- centralize tokens in one file
- use preview data for fast iteration