/**
 * Measure piece geometry from a FreeSewing SVG.
 * Path data stays in the part's own coordinate space (millimetres).
 */

const TOKEN = /NaN|Infinity|-?\d*\.?\d+(?:e[-+]?\d+)?|[a-zA-Z]/g

function cubic(p0, p1, p2, p3, t) {
  const u = 1 - t
  const x =
    u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
  const y =
    u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
  return { x, y }
}

export function flattenPath(d, steps = 16) {
  const tokens = String(d).match(TOKEN) || []
  let i = 0
  let cx = 0
  let cy = 0
  let sx = 0
  let sy = 0
  const points = []
  const segments = []
  const lineTo = (x, y) => {
    if (!Number.isFinite(x) || !Number.isFinite(y)) return
    if (!Number.isFinite(cx) || !Number.isFinite(cy)) {
      cx = x
      cy = y
      points.push({ x, y })
      return
    }
    segments.push({
      x1: cx,
      y1: cy,
      x2: x,
      y2: y,
      length: Math.hypot(x - cx, y - cy),
    })
    cx = x
    cy = y
    points.push({ x, y })
  }
  while (i < tokens.length) {
    const command = tokens[i]
    if (!/[a-zA-Z]/.test(command)) break
    i += 1
    if (command === 'M' || command === 'L') {
      const x = Number(tokens[i])
      const y = Number(tokens[i + 1])
      i += 2
      if (!Number.isFinite(x) || !Number.isFinite(y)) continue
      if (command === 'M') {
        cx = sx = x
        cy = sy = y
        points.push({ x, y })
      } else lineTo(x, y)
    } else if (command === 'C') {
      const p1 = { x: Number(tokens[i]), y: Number(tokens[i + 1]) }
      const p2 = { x: Number(tokens[i + 2]), y: Number(tokens[i + 3]) }
      const p3 = { x: Number(tokens[i + 4]), y: Number(tokens[i + 5]) }
      i += 6
      if (![p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, cx, cy].every(Number.isFinite)) {
        if (Number.isFinite(p3.x) && Number.isFinite(p3.y)) {
          cx = p3.x
          cy = p3.y
        }
        continue
      }
      const p0 = { x: cx, y: cy }
      let prev = p0
      for (let step = 1; step <= steps; step += 1) {
        const point = cubic(p0, p1, p2, p3, step / steps)
        segments.push({
          x1: prev.x,
          y1: prev.y,
          x2: point.x,
          y2: point.y,
          length: Math.hypot(point.x - prev.x, point.y - prev.y),
        })
        points.push(point)
        prev = point
      }
      cx = p3.x
      cy = p3.y
    } else if (command === 'Z' || command === 'z') {
      lineTo(sx, sy)
    } else break
  }
  return { points, segments }
}

/** Drop path commands whose coordinates are not finite. */
export function sanitizePath(d) {
  const tokens = String(d).match(TOKEN) || []
  let index = 0
  const out = []
  const take = (count) => {
    const nums = []
    let ok = true
    for (let step = 0; step < count; step += 1) {
      const value = Number(tokens[index])
      index += 1
      if (!Number.isFinite(value)) ok = false
      nums.push(value)
    }
    return ok ? nums : null
  }
  while (index < tokens.length) {
    const command = tokens[index]
    if (!/[a-zA-Z]/.test(command)) break
    index += 1
    const count = command === 'M' || command === 'L' ? 2 : command === 'C' ? 6 : command === 'Z' || command === 'z' ? 0 : -1
    if (count < 0) break
    if (count === 0) {
      out.push('Z')
      continue
    }
    const nums = take(count)
    if (!nums) continue
    out.push(command, ...nums.map((value) => String(Math.round(value * 100) / 100)))
  }
  return out.join(' ')
}

export function extractGroup(svg, id) {
  const token = `id="${id}"`
  const idAt = svg.indexOf(token)
  if (idAt < 0) return ''
  const tagStart = svg.lastIndexOf('<g', idAt)
  let depth = 0
  let index = tagStart
  while (index < svg.length) {
    const nextOpen = svg.indexOf('<g', index)
    const nextClose = svg.indexOf('</g>', index)
    if (nextClose < 0) return svg.slice(tagStart)
    const opens = nextOpen !== -1 && nextOpen < nextClose
    if (opens) {
      depth += 1
      index = nextOpen + 2
    } else {
      depth -= 1
      index = nextClose + 4
      if (depth === 0) return svg.slice(tagStart, index)
    }
  }
  return ''
}

export function partGroupId(partName) {
  return `fs-stack-${partName}-part-${partName}`
}

export function pathsInPart(svg, partName) {
  const chunk = extractGroup(svg, partGroupId(partName))
  if (!chunk) return []
  const paths = []
  const pattern = /<path\b([^>]*)\/>/g
  let match = pattern.exec(chunk)
  while (match) {
    const attrs = match[1]
    const d = /(?:^|\s)d="([^"]*)"/.exec(attrs)?.[1] || ''
    const className = /class="([^"]*)"/.exec(attrs)?.[1] || ''
    const clean = sanitizePath(d)
    if (clean) paths.push({ d: clean, className, geometry: flattenPath(clean) })
    match = pattern.exec(chunk)
  }
  return paths
}

function classOf(path) {
  return path.className || ''
}

function isSeam(path) {
  const name = classOf(path)
  return name.split(/\s+/).includes('fabric') && !name.split(/\s+/).includes('sa')
}

function isSa(path) {
  const name = classOf(path)
  return name.split(/\s+/).includes('sa')
}

function isHelpLine(path) {
  return classOf(path).split(/\s+/).includes('help')
}

/** Longest near-horizontal help line, preferring the upper one when several match. */
export function chestLineLength(svg, partName) {
  const lines = []
  for (const path of pathsInPart(svg, partName)) {
    if (!isHelpLine(path)) continue
    const { segments } = path.geometry
    if (segments.length !== 1) continue
    const segment = segments[0]
    if (Math.abs(segment.y1 - segment.y2) > 0.2) continue
    if (segment.length < 20) continue
    lines.push({ y: (segment.y1 + segment.y2) / 2, length: segment.length })
  }
  if (!lines.length) return null
  lines.sort((a, b) => a.y - b.y || b.length - a.length)
  return lines[0].length
}

export function verticalSideLength(svg, partName) {
  let best = 0
  for (const path of pathsInPart(svg, partName)) {
    if (!isSeam(path)) continue
    for (const segment of path.geometry.segments) {
      if (Math.abs(segment.x1 - segment.x2) > 0.3) continue
      if (segment.length > best) best = segment.length
    }
  }
  return best || null
}

export function seamMaxY(svg, partName) {
  let max = null
  for (const path of pathsInPart(svg, partName)) {
    if (!isSeam(path)) continue
    for (const point of path.geometry.points) {
      if (max === null || point.y > max) max = point.y
    }
  }
  return max
}

function intersectionsAtY(path, y) {
  const hits = []
  for (const segment of path.geometry.segments) {
    const { y1, y2, x1, x2 } = segment
    if (Math.abs(y1 - y2) < 1e-6) {
      if (Math.abs(y1 - y) < 0.4) {
        hits.push(x1, x2)
      }
      continue
    }
    const minY = Math.min(y1, y2)
    const maxY = Math.max(y1, y2)
    if (y < minY - 0.2 || y > maxY + 0.2) continue
    const t = (y - y1) / (y2 - y1)
    if (t >= -0.02 && t <= 1.02) hits.push(x1 + t * (x2 - x1))
  }
  return hits
}

function chestHelp(svg, partName) {
  const lines = []
  for (const path of pathsInPart(svg, partName)) {
    if (!isHelpLine(path) || path.geometry.segments.length !== 1) continue
    const segment = path.geometry.segments[0]
    if (Math.abs(segment.y1 - segment.y2) > 0.2 || segment.length < 20) continue
    lines.push(segment)
  }
  lines.sort((a, b) => Math.min(a.y1, a.y2) - Math.min(b.y1, b.y2))
  return lines[0] || null
}

/** Cut width of the seam-allowance outline at the chest help-line. */
export function cutWidthAtChest(svg, partName) {
  const chest = chestHelp(svg, partName)
  if (!chest) return null
  const y = (chest.y1 + chest.y2) / 2
  const seamMin = Math.min(chest.x1, chest.x2)
  const seamMax = Math.max(chest.x1, chest.x2)
  const xs = []
  for (const path of pathsInPart(svg, partName)) {
    if (!isSa(path)) continue
    xs.push(...intersectionsAtY(path, y))
  }
  if (!xs.length) return null
  if (xs.length === 1) {
    const extra = Math.max(0, xs[0] - seamMax, seamMin - xs[0])
    return seamMax - seamMin + extra
  }
  return Math.max(...xs) - Math.min(...xs)
}

/** Vertical seam at the outer end of the chest line (the side seam, not the fold). */
export function outerSideLength(svg, partName) {
  const chest = chestHelp(svg, partName)
  if (!chest) return verticalSideLength(svg, partName)
  const outerX = Math.abs(chest.x1) > Math.abs(chest.x2) ? chest.x1 : chest.x2
  let best = 0
  for (const path of pathsInPart(svg, partName)) {
    if (!isSeam(path)) continue
    for (const segment of path.geometry.segments) {
      if (Math.abs(segment.x1 - segment.x2) > 0.4) continue
      if (Math.abs(segment.x1 - outerX) > 0.6) continue
      if (segment.length > best) best = segment.length
    }
  }
  return best || null
}

export function seamBox(svg, partName) {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  let count = 0
  for (const path of pathsInPart(svg, partName)) {
    if (!isSeam(path)) continue
    for (const point of path.geometry.points) {
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

/** Width of the seam at its top or bottom edge. */
export function seamEdgeWidth(svg, partName, edge = 'top') {
  const box = seamBox(svg, partName)
  if (!box) return null
  const y = edge === 'top' ? box.minY : box.maxY
  let minX = Infinity
  let maxX = -Infinity
  let count = 0
  for (const path of pathsInPart(svg, partName)) {
    if (!isSeam(path)) continue
    for (const point of path.geometry.points) {
      if (Math.abs(point.y - y) > 1.5) continue
      count += 1
      minX = Math.min(minX, point.x)
      maxX = Math.max(maxX, point.x)
    }
  }
  if (count < 2) return null
  return maxX - minX
}

export function renderedPartNames(svg) {
  return [...svg.matchAll(/id="fs-stack-(.+?)-part-\1"/g)].map((match) => match[1])
}

export function patternPieces(svg) {
  const pieces = []
  for (const name of renderedPartNames(svg)) {
    const paths = pathsInPart(svg, name).filter((path) => {
      const classes = classOf(path).split(/\s+/)
      return !classes.includes('hidden') && !classes.includes('note')
    })
    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity
    let count = 0
    for (const path of paths) {
      for (const point of path.geometry.points) {
        count += 1
        minX = Math.min(minX, point.x)
        minY = Math.min(minY, point.y)
        maxX = Math.max(maxX, point.x)
        maxY = Math.max(maxY, point.y)
      }
    }
    if (!count) continue
    const width = maxX - minX
    const height = maxY - minY
    if (width < 2 || height < 2) continue
    pieces.push({
      name,
      paths,
      minX,
      minY,
      maxX,
      maxY,
      width,
      height,
    })
  }
  pieces.sort((a, b) => a.name.localeCompare(b.name))
  return pieces
}

export function sumLengths(svg, partNames, reader) {
  let total = 0
  for (const name of partNames) {
    const value = reader(svg, name)
    if (value == null) return null
    total += value
  }
  return total
}
