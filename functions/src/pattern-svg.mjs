/**
 * FreeSewing's render() leaves the style block empty, so a plain SVG viewer
 * fills closed pieces and draws hidden marks. This keeps the sewing marks
 * (grainline, cut-on-fold, fold lines, notches) and hides construction lines,
 * logos, and the FreeSewing title block.
 */

import { flattenPath } from './geometry.mjs'

const OUTLINE_CSS = `
.hidden, .note:not(.sewlens-mark), .logo, .help:not(.sewlens-mark), .scalebox {
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
  if (classes.includes('sewlens-mark')) {
    next = next.replace(/\sstyle="[^"]*"/g, '')
    next += ' style="display:inline"'
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

/** Drop note/help so a viewer that ignores :not() still strokes the mark. */
function markAttrs(attrs) {
  const classes = classList(attrs).filter((name) => name !== 'note' && name !== 'help' && name !== 'hidden')
  if (!classes.includes('sewlens-mark')) classes.push('sewlens-mark')
  const painted = /class="/.test(attrs)
    ? attrs.replace(/class="[^"]*"/, `class="${classes.join(' ')}"`)
    : `${attrs} class="${classes.join(' ')}"`
  return painted
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
    const foldLine = classes.includes('note') && classes.includes('help')
      && !/grainline|cutonfold/i.test(`${markers.start}${markers.end}`)
    let painted = markAttrs(attrs)
    const label = labels.get(attr(attrs, 'id')) || labelByD.get(markD(attr(attrs, 'd'))) || ''
    if (label && !/data-sewlens-label=/.test(painted)) {
      painted += ` data-sewlens-label="${label.replace(/"/g, '')}"`
    }
    if (foldLine) painted += ' data-sewlens-fold="1"'
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

function round(value) {
  return Math.round(value * 100) / 100
}

function groupBounds(svg, idIndex) {
  const open = svg.lastIndexOf('<g', idIndex)
  if (open < 0) return null
  const tags = /<\/?g\b[^>]*>/g
  tags.lastIndex = open
  let depth = 0
  let match = tags.exec(svg)
  while (match) {
    if (match[0].startsWith('</')) {
      depth -= 1
      if (depth === 0) return { open, close: match.index }
    } else depth += 1
    match = tags.exec(svg)
  }
  return null
}

function partIdAt(svg, part) {
  const names = [part, String(part).split('.').pop()].filter(Boolean)
  for (const name of names) {
    const token = `id="fs-stack-${name}-part-${name}"`
    const at = svg.indexOf(token)
    if (at >= 0) return at
  }
  return -1
}

function boxOf(inner, className) {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  let count = 0
  const pattern = className
    ? new RegExp(`<path\\b([^>]*class="[^"]*\\b${className}\\b[^"]*"[^>]*)\\/>`, 'g')
    : /<path\b([^>]*)\/>/g
  for (const match of inner.matchAll(pattern)) {
    const geometry = flattenPath(attr(match[1], 'd'))
    for (const point of geometry.points) {
      count += 1
      minX = Math.min(minX, point.x)
      minY = Math.min(minY, point.y)
      maxX = Math.max(maxX, point.x)
      maxY = Math.max(maxY, point.y)
    }
  }
  if (!count) return null
  return { minX, minY, maxX, maxY, width: maxX - minX, height: maxY - minY }
}

/** Spread parallel fold labels along the line so they do not sit on top of each other. */
function foldAlong(x) {
  const slot = Math.abs(Math.round(Number(x) || 0)) % 4
  return 0.36 + slot * 0.15
}

/** A real grainline, not a fold line and not a cut-on-fold bracket. */
function hasGrainline(inner) {
  for (const match of inner.matchAll(/<path\b([^>]*\bsewlens-mark\b[^>]*)\/>/g)) {
    const attrs = match[1]
    if (attr(attrs, 'data-sewlens-fold') === '1') continue
    const synthetic = attr(attrs, 'data-sewlens-grain') === '1'
    const marked = /marker-(?:start|end)="[^"]*grainline/i.test(attrs)
    if (!synthetic && !marked) continue
    const geometry = flattenPath(attr(attrs, 'd'))
    if (geometry.segments.some((segment) => segment.length > 12)) return true
  }
  return false
}

/** One "Fold here" per fold line, offset from the line and from the piece number. */
function singleFoldLabels(svg) {
  const phrases = new Set()
  for (const match of svg.matchAll(/<path\b([^>]*data-sewlens-fold="1"[^>]*)\/>/g)) {
    const label = attr(match[1], 'data-sewlens-label')
    if (label) phrases.add(label)
  }
  if (!phrases.size) return svg
  let next = svg.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g, (block) => {
    const text = collapseRepeats(textOf(block))
    return phrases.has(text) ? '' : block
  })
  next = next.replace(/<path\b([^>]*data-sewlens-fold="1"[^>]*)\/>/g, (full, attrs) => {
    const label = attr(attrs, 'data-sewlens-label')
    const points = linePoints(attr(attrs, 'd'))
    if (!label || points.length < 2) return full
    const start = points[0]
    const end = points[points.length - 1]
    const along = foldAlong(start.x)
    const x = start.x + (end.x - start.x) * along
    const y = start.y + (end.y - start.y) * along
    const dx = end.x - start.x
    const dy = end.y - start.y
    const length = Math.hypot(dx, dy) || 1
    const ox = (-dy / length) * 7
    const oy = (dx / length) * 7
    const text = `<text class="sewlens-fold-label" font-size="8"><tspan x="${round(x + ox)}" y="${round(y + oy)}">${label}</tspan></text>`
    return `${full}${text}`
  })
  return next
}

function escapeText(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function stampCutCount(svg, idIndex, text) {
  const open = svg.lastIndexOf('<g', idIndex)
  const end = svg.indexOf('>', idIndex)
  if (open < 0 || end < 0) return svg
  const tag = svg.slice(open, end)
  if (/data-sewlens-cut="/.test(tag)) return svg
  const stamped = tag.replace('<g', `<g data-sewlens-cut="${escapeText(text)}"`)
  return svg.slice(0, open) + stamped + svg.slice(end)
}

function isCutInstruction(text, cutWord) {
  const plain = collapseRepeats(String(text))
  if (!plain || !cutWord || !/\d/.test(plain)) return false
  return plain.toLowerCase().includes(String(cutWord).toLowerCase())
}

function cutTextElement(block, phrase) {
  const open = /^<text\b[^>]*>/.exec(block)?.[0] || '<text class="sewlens-cut" font-size="8">'
  const x = /<text\b[^>]*\sx="([^"]+)"/.exec(block)?.[1]
    || /<tspan\b[^>]*\sx="([^"]+)"/.exec(block)?.[1]
    || '4'
  const y = /<text\b[^>]*\sy="([^"]+)"/.exec(block)?.[1]
    || /<tspan\b[^>]*\sy="([^"]+)"/.exec(block)?.[1]
    || '20'
  return `${open}<tspan x="${x}" y="${y}">${escapeText(phrase)}</tspan></text>`
}

/** The visible cut count is the same phrase the PDF draws, from cutLinesFromStore. */
function addCutCounts(svg, lines) {
  let next = svg
  for (const line of lines) {
    let idIndex = partIdAt(next, line.part)
    if (idIndex < 0 || !line.text) continue
    next = stampCutCount(next, idIndex, line.text)
    idIndex = partIdAt(next, line.part)
    const bounds = groupBounds(next, idIndex)
    if (!bounds) continue
    let inner = next.slice(bounds.open, bounds.close)
    let kept = false
    inner = inner.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g, (block) => {
      const visible = collapseRepeats(textOf(block))
      if (visible === line.text) {
        if (kept) return ''
        kept = true
        return block
      }
      if (!isCutInstruction(visible, line.cutWord)) return block
      if (kept) return ''
      kept = true
      return cutTextElement(block, line.text)
    })
    if (!kept) {
      const box = boxOf(inner, 'fabric') || boxOf(inner, '')
      const x = box ? box.minX + Math.min(8, box.width * 0.12) : 4
      const y = box ? box.minY + box.height * 0.42 : 20
      inner += `<text class="sewlens-cut" data-sewlens-cut="1" font-size="8"><tspan x="${round(x)}" y="${round(y)}">${escapeText(line.text)}</tspan></text>`
    }
    next = `${next.slice(0, bounds.open)}${inner}${next.slice(bounds.close)}`
  }
  return next
}

/** A point on the long axis that does not sit on a fold line. */
function clearOfFolds(box, vertical, inner) {
  const folds = []
  for (const match of inner.matchAll(/<path\b([^>]*data-sewlens-fold="1"[^>]*)\/>/g)) {
    const points = linePoints(attr(match[1], 'd'))
    if (points.length) folds.push(vertical ? points[0].x : points[0].y)
  }
  const min = vertical ? box.minX : box.minY
  const max = vertical ? box.maxX : box.maxY
  let best = (min + max) / 2
  if (!folds.length || max - min < 4) return best
  let bestDist = -1
  for (let value = min + 1; value <= max - 1; value += 1) {
    let dist = max - min
    for (const fold of folds) dist = Math.min(dist, Math.abs(fold - value))
    if (dist > bestDist) {
      bestDist = dist
      best = value
    }
  }
  return best
}

/** Every piece gets a grainline. A fold line does not count. */
function ensureGrainOrFold(svg, grainlineLabel) {
  const ids = [...svg.matchAll(/id="(fs-stack-(.+?)-part-\2)"/g)]
  let next = svg
  for (const match of ids) {
    const idIndex = next.indexOf(`id="${match[1]}"`)
    if (idIndex < 0) continue
    const bounds = groupBounds(next, idIndex)
    if (!bounds) continue
    const inner = next.slice(bounds.open, bounds.close)
    if (hasGrainline(inner)) continue
    const box = boxOf(inner, 'fabric') || boxOf(inner, '')
    if (!box || box.width < 8 || box.height < 8) continue
    const vertical = box.height >= box.width
    const inset = 0.18
    const axis = clearOfFolds(box, vertical, inner)
    const x1 = vertical ? axis : box.minX + box.width * inset
    const x2 = vertical ? axis : box.maxX - box.width * inset
    const y1 = vertical ? box.minY + box.height * inset : axis
    const y2 = vertical ? box.maxY - box.height * inset : axis
    const label = grainlineLabel || 'Grainline'
    const path = `<path class="sewlens-mark" data-sewlens-grain="1" data-sewlens-label="${escapeText(label)}" d="M ${round(x1)} ${round(y1)} L ${round(x2)} ${round(y2)}"/>`
    const arrows = arrowPath(`M ${x1} ${y1} L ${x2} ${y2}`, { start: '', end: 'grainline' })
    const head = arrows ? `<path class="sewlens-mark" d="${arrows}"/>` : ''
    next = `${next.slice(0, bounds.close)}${path}${head}${next.slice(bounds.close)}`
  }
  return next
}

/** Outline styling, sewing marks, and no FreeSewing title or patron block. */
export function stylePatternSvg(svg, extras = {}) {
  let next = stripCustomerNoise(String(svg))
  next = keepSewerMarks(next)
  next = singleFoldLabels(next)
  next = addCutCounts(next, extras.cutLines || [])
  next = ensureGrainOrFold(next, extras.grainlineLabel)
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
