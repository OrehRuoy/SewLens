/**
 * FreeSewing's render() leaves the style block empty, so a plain SVG viewer
 * fills closed pieces and draws hidden marks. This keeps the sewing marks
 * (grainline, cut-on-fold, fold lines, notches) and hides construction lines,
 * logos, and the FreeSewing title block.
 */

const OUTLINE_CSS = `
.hidden, .note, .logo, .help, .scalebox {
  display: none !important;
  stroke: none !important;
  fill: none !important;
}
.sewlens-mark {
  display: inline !important;
  fill: none !important;
  stroke: #212121 !important;
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

const DROP_TEXT = /FreeSewing|ephemeral|patron|should measure|sollte messen|doit mesurer|debe medir|deve medir|deve misurare|moet meten|この枠|Chest Line|Waist Line|\bv\d+\.\d+\.\d+\b|\b20\d{2}\b/i

function classList(attrs) {
  return (/class="([^"]*)"/.exec(attrs)?.[1] || '').split(/\s+/).filter(Boolean)
}

function attr(attrs, name) {
  return new RegExp(`(?:^|\\s)${name}="([^"]*)"`).exec(attrs)?.[1] || ''
}

function hideElement(attrs) {
  const classes = classList(attrs)
  if (classes.includes('sewlens-mark')) return false
  const href = attr(attrs, 'xlink:href') || attr(attrs, 'href')
  return classes.includes('hidden')
    || classes.includes('note')
    || classes.includes('help')
    || classes.includes('logo')
    || classes.includes('scalebox')
    || href.includes('#logo')
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

function decodeText(value) {
  return String(value)
    .replace(/&#160;/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#8220;|&#8221;|&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim()
}

/** "Fold here Fold here" collapses to "Fold here". A single phrase stays as written. */
function collapseRepeats(value) {
  const words = decodeText(value).split(' ').filter(Boolean)
  if (!words.length) return ''
  for (let size = 1; size <= Math.floor(words.length / 2); size += 1) {
    const phrase = words.slice(0, size)
    const repeats = words.length % size === 0 && words.every((word, index) => word === phrase[index % size])
    if (repeats) return phrase.join(' ')
  }
  return words.join(' ')
}

function textOf(block) {
  return decodeText(block.replace(/<[^>]+>/g, ' '))
}

function stripCustomerNoise(svg) {
  let next = svg.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g, (block) => (DROP_TEXT.test(textOf(block)) ? '' : block))
  next = next.replace(/<path\b[^>]*class="[^"]*\bscalebox\b[^"]*"[^>]*\/>/g, '')
  return next
}

function labelsByPath(svg) {
  const byId = new Map()
  const pattern = /<textPath\b[^>]*?(?:xlink:href|href)="#([^"]+)"[^>]*>[\s\S]*?<tspan\b[^>]*>([\s\S]*?)<\/tspan>/g
  for (const match of svg.matchAll(pattern)) {
    const label = collapseRepeats(match[2])
    if (label && !DROP_TEXT.test(label)) byId.set(match[1], label)
  }
  return byId
}

function withClass(attrs, name) {
  if (classList(attrs).includes(name)) return attrs
  if (/class="/.test(attrs)) return attrs.replace(/class="([^"]*)"/, `class="$1 ${name}"`)
  return `${attrs} class="${name}"`
}

function arrowHead(x, y, angle) {
  const length = 7
  const spread = 0.42
  const x1 = x - Math.cos(angle - spread) * length
  const y1 = y - Math.sin(angle - spread) * length
  const x2 = x - Math.cos(angle + spread) * length
  const y2 = y - Math.sin(angle + spread) * length
  const n = (value) => Math.round(value * 100) / 100
  return `M ${n(x1)} ${n(y1)} L ${n(x)} ${n(y)} L ${n(x2)} ${n(y2)}`
}

function linePoints(d) {
  const points = []
  for (const match of String(d).matchAll(/[ML]\s*(-?\d*\.?\d+)[,\s]+(-?\d*\.?\d+)/gi)) {
    points.push({ x: Number(match[1]), y: Number(match[2]) })
  }
  return points
}

function arrowPath(d, markers) {
  const points = linePoints(d)
  if (points.length < 2) return ''
  const parts = []
  if (/grainline|cutonfold/i.test(markers.start || '')) {
    const from = points[0]
    const to = points[1]
    parts.push(arrowHead(from.x, from.y, Math.atan2(from.y - to.y, from.x - to.x)))
  }
  if (/grainline|cutonfold/i.test(markers.end || '')) {
    const from = points[points.length - 2]
    const to = points[points.length - 1]
    parts.push(arrowHead(to.x, to.y, Math.atan2(to.y - from.y, to.x - from.x)))
  }
  return parts.join(' ')
}

function notchPath(kind, x, y) {
  if (kind === 'bnotch') {
    const s = 2.2
    return `M ${x - s} ${y - s} L ${x + s} ${y + s} M ${x + s} ${y - s} L ${x - s} ${y + s}`
  }
  const r = 2.2
  const k = r * 0.551915
  const n = (value) => Math.round(value * 100) / 100
  return [
    `M ${n(x - r)} ${n(y)}`,
    `C ${n(x - r)} ${n(y - k)} ${n(x - k)} ${n(y - r)} ${n(x)} ${n(y - r)}`,
    `C ${n(x + k)} ${n(y - r)} ${n(x + r)} ${n(y - k)} ${n(x + r)} ${n(y)}`,
    `C ${n(x + r)} ${n(y + k)} ${n(x + k)} ${n(y + r)} ${n(x)} ${n(y + r)}`,
    `C ${n(x - k)} ${n(y + r)} ${n(x - r)} ${n(y + k)} ${n(x - r)} ${n(y)}`,
  ].join(' ')
}

function markD(d) {
  return String(d).replace(/\s+/g, '')
}

/** Grainline, fold lines, arrows, and notches become real stroked paths. */
function keepSewerMarks(svg) {
  const labels = labelsByPath(svg)
  const labelByD = new Map()
  for (const match of svg.matchAll(/<path\b([^>]*)\/>/g)) {
    const id = attr(match[1], 'id')
    const label = labels.get(id)
    if (label) labelByD.set(markD(attr(match[1], 'd')), label)
  }
  let next = svg.replace(/<path\b([^>]*)\/>/g, (full, attrs) => {
    const classes = classList(attrs)
    const hidden = classes.includes('hidden')
    const markers = {
      start: attr(attrs, 'marker-start'),
      end: attr(attrs, 'marker-end'),
    }
    const marked = !hidden && (
      /grainline|cutonfold/i.test(`${markers.start}${markers.end}`)
      || (classes.includes('note') && classes.includes('help'))
    )
    if (!marked) return full
    let painted = withClass(attrs, 'sewlens-mark')
    const label = labels.get(attr(attrs, 'id')) || labelByD.get(markD(attr(attrs, 'd'))) || ''
    if (label && !/data-sewlens-label=/.test(painted)) {
      painted += ` data-sewlens-label="${label.replace(/"/g, '')}"`
    }
    const arrows = arrowPath(attr(attrs, 'd'), markers)
    const head = arrows
      ? `<path class="sewlens-mark" d="${arrows}"/>`
      : ''
    return `<path${painted}/>${head}`
  })
  next = next.replace(/<use\b([^>]*?)\/>|<use\b([^>]*?)>\s*<\/use>/g, (full, selfClosed, paired) => {
    const attrs = selfClosed || paired
    const href = attr(attrs, 'xlink:href') || attr(attrs, 'href')
    const kind = href.includes('#bnotch') ? 'bnotch' : href.includes('#notch') ? 'notch' : ''
    if (!kind) return full
    const x = Number(attr(attrs, 'x'))
    const y = Number(attr(attrs, 'y'))
    if (!Number.isFinite(x) || !Number.isFinite(y)) return full
    return `<path class="sewlens-mark" d="${notchPath(kind, x, y)}"/>`
  })
  return next
}

/** Outline styling, sewing marks, and no FreeSewing title or patron block. */
export function stylePatternSvg(svg) {
  let next = stripCustomerNoise(String(svg))
  next = keepSewerMarks(next)
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
