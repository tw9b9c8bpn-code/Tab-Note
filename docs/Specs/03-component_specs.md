# component specs

## settings window

### structure
- top toolbar area
- left sidebar for categories
- right detail panel for current section

### behavior
- sidebar remains visually quiet
- selected row clearly highlighted
- detail panel scrolls independently
- sections should be chunked into cards or spaced groups

---

## sidebar row

### intent
Allow fast scanning across categories.

### layout
- horizontal row
- leading icon
- label
- optional trailing indicator

### rules
- height: comfortable, not oversized
- selected state should be obvious but restrained
- icon and text aligned cleanly
- no heavy borders around each item

### do
- use subtle background for selected row
- keep labels short

### dont
- don’t use bright fills for all rows
- don’t over-round row backgrounds

---

## settings card

### intent
Group related controls into a single visual unit.

### layout
- vertical stack
- internal padding: 16
- spacing between controls: 12 to 16
- optional header
- optional footer/helper text

### rules
- use system secondary background
- radius: 12 to 14
- border only if needed for separation
- keep card width aligned with surrounding content

### do
- use for related toggles, pickers, text fields
- split very long forms into multiple cards

### dont
- don’t dump the whole page into one giant card
- don’t mix unrelated settings together

---

## section header

### intent
Introduce a group without shouting.

### layout
- title
- optional short description below

### rules
- title stronger than body
- description muted
- generous space above section, tighter space below title

---

## toggle row

### intent
Present a binary preference with clear explanation.

### layout
- left: label + optional helper text
- right: toggle

### rules
- vertical alignment should feel centered
- helper text should wrap cleanly
- avoid long paragraphs

---

## segmented control

### intent
Switch between closely related view states.

### rules
- only use for small mutually exclusive sets
- 2 to 5 options ideal
- labels should be short
- avoid inside crowded cards unless clearly needed

---

## text field row

### intent
Collect short structured input.

### rules
- label above or leading depending on density
- helper/error text directly tied to field
- width should match expected input length
- avoid giant full-width text fields for tiny values

---

## primary button

### intent
Drive the main action in a local area.

### rules
- only one dominant primary action per section
- accent color allowed here
- strong label, short text
- surrounding actions should be secondary/quiet

---

## destructive action

### intent
Handle risky actions without accidental clicks.

### rules
- visually separated from routine controls
- use destructive color semantics
- add confirmation if consequence is meaningful