# Acid2 Test Support

This document describes the current state of Acid2 test support in DOPBrowser.

## Overview

The Acid2 test is a comprehensive test of CSS 2.1 features designed by the Web Standards Project. It tests many advanced CSS features including positioning, floats, borders, selectors, and more.

## Current Status

DOPBrowser now fetches and processes the **real Acid2 test** from webstandards.org (not a simplified approximation). The enhanced CSS parser and selector matching system handle many of the test's requirements.

## Implemented Features

### CSS Selectors (Enhanced)
- ✅ Element selectors (`div`, `p`)
- ✅ ID selectors (`#id`)
- ✅ Class selectors (`.class`)
- ✅ Multiple class selectors (`.class1.class2`)
- ✅ Attribute selectors (`[attr]`, `[attr=value]`, `[attr~=value]`)
- ✅ Descendant combinator (space)
- ✅ Child combinator (`>`)
- ✅ Adjacent sibling combinator (`+`)
- ✅ Universal selector (`*`)

### CSS Properties (Enhanced)
- ✅ Position: static, relative, absolute, fixed
- ✅ Float: none, left, right
- ✅ Clear: none, left, right, both
- ✅ Display: block, inline, none
- ✅ Visibility: visible, hidden
- ✅ Overflow: visible, hidden
- ✅ Width, Height (px, %, em, mm, auto)
- ✅ Min-width, Max-width, Min-height, Max-height
- ✅ Margin (all sides, shorthand)
- ✅ Padding (all sides, shorthand)
- ✅ Border width, style, color (per side)
- ✅ Top, Right, Bottom, Left offsets
- ✅ Z-index
- ✅ Background-color, Color
- ✅ Named colors (extended set including navy, maroon, olive, etc.)

### Units
- ✅ Pixels (px)
- ✅ Percentages (%)
- ✅ Em units (em)
- ✅ Millimeters (mm)

### Border Styles
- ✅ none
- ✅ solid
- ✅ dotted
- ✅ dashed

## Features Not Yet Implemented

The following CSS 2.1 features required for perfect Acid2 compliance are not yet implemented:

### Layout Engine Limitations
- ❌ Float layout algorithm (floats are parsed but not laid out)
- ❌ Inline box model and baseline alignment
- ❌ Margin collapsing
- ❌ Line-height and vertical-align
- ❌ Text wrapping around floats
- ❌ Shrink-to-fit width calculation

### Rendering Limitations
- ❌ Border rendering (borders are parsed but not drawn)
- ❌ Data URLs for background images
- ❌ Fixed background positioning
- ❌ Background image rendering
- ❌ Text rendering with proper font metrics

### Advanced CSS Features
- ❌ Pseudo-classes (`:hover`, `:link`, `:visited`, `:before`, `:after`)
- ❌ Content generation (`content: ""`)
- ❌ Inherit keyword
- ❌ CSS specificity calculation (currently uses cascade order only)
- ❌ !important declarations

### Other Features
- ❌ Object/embed elements
- ❌ Table layout
- ❌ Form elements

## Architecture Constraints

DOPBrowser is built around the **Content-- v6.0 specification**, which is a performance-oriented UI language that intentionally sacrifices some CSS features for speed:

1. **No Inline Box Flow**: Cannot place interactive elements inside flowing text
2. **No Contextual Selectors**: Limited support for arbitrary parent/sibling context (now improved)
3. **No Text Floats**: Cannot wrap text around non-rectangular shapes
4. **Limited Global Text Selection**: Selection is difficult across different text nodes

These architectural decisions mean that achieving 100% Acid2 compliance would require fundamental changes to the browser's design philosophy.

## What Has Been Improved

This refactoring has significantly enhanced DOPBrowser's CSS capabilities:

1. **Advanced Selector Matching**: The browser can now parse and match complex selectors including attribute selectors, multiple classes, and combinators.

2. **Border Property Parsing**: Full support for border shorthand and individual side properties (width, style, color).

3. **Float and Clear**: Properties are now parsed and stored (layout implementation pending).

4. **Min/Max Constraints**: Min and max width/height are parsed and can be applied.

5. **Extended Color Support**: More named colors matching CSS 2.1 specification.

6. **Unit Support**: Added millimeter unit support used by Acid2.

## Testing

The Acid2 test can be rendered using:

```bash
julia --project=. scripts/render_acid2.jl
```

This script:
1. Fetches the real Acid2 test from webstandards.org
2. Parses the HTML and CSS with enhanced selector support
3. Applies styles using the improved CSS cascade
4. Renders to `acid2.png`

## Future Work

To achieve full Acid2 compliance, the following work would be needed:

1. **Float Layout Engine**: Implement the CSS 2.1 float positioning algorithm
2. **Inline Layout**: Proper inline box model with baseline alignment
3. **Border Rendering**: Draw borders with correct styles and colors
4. **Image Support**: Data URLs and background image rendering
5. **Pseudo-elements**: Support for `:before` and `:after` with content generation
6. **Specificity**: Proper CSS specificity calculation for selector matching

Each of these represents a significant engineering effort.

## Conclusion

While perfect Acid2 compliance is not yet achieved, DOPBrowser has been significantly enhanced to parse and understand most of the Acid2 test's CSS. The main limitations are in the layout and rendering engines, which would require architectural changes to fully implement CSS 2.1's complex layout algorithms.

The browser now successfully processes the real Acid2 test (not a simplified version) and has comprehensive CSS selector and property support. This provides a strong foundation for future enhancements.
