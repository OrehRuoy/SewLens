/**
 * FreeSewing's render() leaves the style block empty, so a plain SVG viewer
 * fills closed pieces and draws hidden marks. This adds outline styling that
 * those viewers, including Godot's SVG loader, can apply.
 */

const OUTLINE_CSS = `
.hidden, .note, .logo {
  display: none !important;
  stroke: none !important;
  fill: none !important;
}
path, circle, ellipse, polygon, polyline, rect {
  fill: none;
}
text, tspan {
  fill: #161616;
  stroke: none;
}
`

const DRAW_TAGS = ['path', 'circle', 'ellipse', 'polygon', 'polyline', 'rect', 'use']

function classList(attrs) {
  return (/class="([^"]*)"/.exec(attrs)?.[1] || '').split(/\s+/).filter(Boolean)
}

function hideElement(attrs) {
  const classes = classList(attrs)
  const href = /(?:xlink:href|href)="([^"]*)"/.exec(attrs)?.[1] || ''
  return classes.includes('hidden') || classes.includes('note') || classes.includes('logo') || href.includes('#logo')
}

function paintAttrs(tag, attrs) {
  const classes = classList(attrs)
  let next = attrs
  if (hideElement(attrs)) {
    next = next.replace(/\s(?:fill|stroke|stroke-width|style)="[^"]*"/g, '')
    return `${next} fill="none" stroke="none" style="display:none"`
  }
  if (tag === 'use') return next
  const filledMark = classes.some((name) => name === 'fill-mark' || name === 'fill-contrast')
  if (!filledMark) {
    if (/\sfill="/.test(next)) next = next.replace(/\sfill="[^"]*"/, ' fill="none"')
    else next += ' fill="none"'
  }
  if (!/\sstroke="/.test(next) && !classes.includes('no-stroke')) next += ' stroke="#212121"'
  return next
}

/** Non-empty outline CSS, hidden marks, and presentation attributes for plain renderers. */
export function stylePatternSvg(svg) {
  let next = String(svg)
  if (next.includes(']]>')) next = next.replace(']]>', `${OUTLINE_CSS}]]>`)
  else {
    next = next.replace(
      /<svg\b[^>]*>/,
      (tag) => `${tag}\n<style type="text/css"><![CDATA[${OUTLINE_CSS}]]></style>\n`
    )
  }
  const pattern = new RegExp(`<(${DRAW_TAGS.join('|')})\\b([^>]*?)(\\/?)>`, 'g')
  next = next.replace(pattern, (full, tag, attrs, close) => `<${tag}${paintAttrs(tag, attrs)}${close}>`)
  return next
}
