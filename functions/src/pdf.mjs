import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import fontkit from '@pdf-lib/fontkit'
import {
  clip,
  endPath,
  PDFDocument,
  popGraphicsState,
  pushGraphicsState,
  rectangle,
  rgb,
} from 'pdf-lib'
import { pieceLabel, uiLabels } from './labels.mjs'
import { PAPER_MM, PT_PER_IN, PT_PER_MM } from './units.mjs'

const fontDirectory = join(dirname(fileURLToPath(import.meta.url)), '../fonts')

const MARGIN_MM = 12
const BLACK = rgb(0, 0, 0)

function wrapText(font, text, size, maxWidth) {
  const source = String(text)
  const tokens = source.includes(' ') ? source.split(/\s+/) : [...source]
  const lines = []
  let line = ''
  const joiner = source.includes(' ') ? ' ' : ''
  for (const token of tokens) {
    const next = line ? `${line}${joiner}${token}` : token
    if (font.widthOfTextAtSize(next, size) <= maxWidth) {
      line = next
      continue
    }
    if (line) lines.push(line)
    line = token
  }
  if (line) lines.push(line)
  return lines.length ? lines : ['']
}

export async function renderPatternPdf({
  paper,
  locale,
  pieces,
  yardage,
  legend,
  seamAllowanceMm,
  units,
}) {
  const size = PAPER_MM[paper]
  const doc = await PDFDocument.create()
  doc.registerFontkit(fontkit)
  const fontBytes = readFileSync(
    join(fontDirectory, locale === 'ja' ? 'KosugiMaru-Regular.woff' : 'NotoSans-Regular.ttf')
  )
  const font = await doc.embedFont(fontBytes, { subset: true })
  const labels = uiLabels(locale)
  const pageWidth = size.width * PT_PER_MM
  const pageHeight = size.height * PT_PER_MM
  const placed = layoutPieces(pieces, paper)
  const grid = patternCells(placed)
  const printed = grid.filter((cell) => !cell.blank)

  drawCalibrationPage(doc.addPage([pageWidth, pageHeight]), {
    font,
    labels,
    legend,
    yardage,
    units,
    seamAllowanceMm,
    pageWidth,
    pageHeight,
  })

  printed.forEach((cell, index) => {
    const page = doc.addPage([pageWidth, pageHeight])
    drawPatternPage(page, {
      font,
      locale,
      pieces: placed.pieces,
      cell,
      contentW: placed.contentW,
      contentH: placed.contentH,
      pageWidth,
      pageHeight,
      labels,
      gridSize: printed.length,
      index: index + 1,
    })
  })

  drawAssemblyPage(doc.addPage([pageWidth, pageHeight]), {
    font,
    labels,
    grid,
    cols: placed.cols,
    pageWidth,
    pageHeight,
  })

  return doc.save()
}

/** Printable area and the row × column grid that covers every placed piece. */
export function layoutPieces(pieces, paper) {
  const size = PAPER_MM[paper]
  const contentW = size.width - MARGIN_MM * 2
  const contentH = size.height - MARGIN_MM * 2 - 8
  const placed = placePieces(pieces, contentW)
  const rows = Math.max(1, Math.ceil(placed.canvasHeight / contentH) || 1)
  const cols = Math.max(1, Math.ceil(placed.canvasWidth / contentW) || 1)
  return { ...placed, contentW, contentH, rows, cols }
}

function placePieces(pieces, contentW) {
  const gap = 8
  let x = 0
  let y = 0
  let rowHeight = 0
  const placedPieces = pieces.map((piece) => ({ ...piece }))
  for (const piece of placedPieces) {
    if (x > 0 && x + piece.width > contentW) {
      y += rowHeight + gap
      x = 0
      rowHeight = 0
    }
    piece.placeX = x
    piece.placeY = y
    x += piece.width + gap
    rowHeight = Math.max(rowHeight, piece.height)
  }
  let canvasWidth = 0
  let canvasHeight = 0
  for (const piece of placedPieces) {
    canvasWidth = Math.max(canvasWidth, piece.placeX + piece.width)
    canvasHeight = Math.max(canvasHeight, piece.placeY + piece.height)
  }
  return { pieces: placedPieces, canvasWidth, canvasHeight }
}

function drawCalibrationPage(page, context) {
  const { font, labels, legend, yardage, units, seamAllowanceMm, pageHeight } = context
  const metric = 100 * PT_PER_MM
  const imperial = 4 * PT_PER_IN
  let top = pageHeight - MARGIN_MM * PT_PER_MM
  const x = MARGIN_MM * PT_PER_MM
  top -= metric
  page.drawRectangle({ x, y: top, width: metric, height: metric, borderWidth: 1.25, borderColor: BLACK })
  page.drawText(labels.testSquareMetric, { x, y: top - 12, size: 9, font, color: BLACK })
  top -= 18 + imperial
  page.drawRectangle({ x, y: top, width: imperial, height: imperial, borderWidth: 1.25, borderColor: BLACK })
  page.drawText(labels.testSquareImperial, { x, y: top - 12, size: 9, font, color: BLACK })

  const textX = x + imperial + 16
  const maxWidth = context.pageWidth - textX - MARGIN_MM * PT_PER_MM
  let textY = pageHeight - MARGIN_MM * PT_PER_MM - 12
  const write = (text, size = 9) => {
    for (const line of wrapText(font, text, size, Math.max(40, maxWidth))) {
      if (textY < MARGIN_MM * PT_PER_MM) return
      page.drawText(line, { x: textX, y: textY, size, font, color: BLACK })
      textY -= size + 3
    }
  }
  write(labels.scale, 10)
  write(labels.legend, 11)
  for (const line of legend) write(line, 8)
  write(labels.seamAllowance + ': ' + (units === 'imperial'
    ? `${(seamAllowanceMm / 25.4).toFixed(3)} in`
    : `${(seamAllowanceMm / 10).toFixed(2)} cm`), 8)
  write(labels.yardage, 11)
  for (const row of yardage) {
    const length = units === 'imperial' ? `${(row.lengthMm / 25.4).toFixed(1)} in` : `${(row.lengthMm / 10).toFixed(1)} cm`
    const fabric = row.fabricCm === 112 ? labels.fabric112 : labels.fabric150
    write(`${fabric}: ${length}`, 8)
  }
}

function patternCells(placed) {
  const cells = []
  for (let row = 0; row < placed.rows; row += 1) {
    for (let col = 0; col < placed.cols; col += 1) {
      const cell = { row, col, id: `${String.fromCharCode(65 + row)}${col + 1}` }
      cell.blank = !cellHasContent(placed.pieces, cell, placed.contentW, placed.contentH)
      cells.push(cell)
    }
  }
  return cells
}

/** Full grid, including blank cells that are left off the printed sheets. */
export function patternGrid(pieces, paper) {
  const placed = layoutPieces(pieces, paper)
  const cells = patternCells(placed)
  return { ...placed, cells, printed: cells.filter((cell) => !cell.blank) }
}

function drawPatternPage(page, context) {
  const { font, locale, pieces, cell, contentW, contentH, pageHeight, labels, gridSize, index } = context
  const windowX = cell.col * contentW
  const windowY = cell.row * contentH
  const clipX = MARGIN_MM * PT_PER_MM
  const clipY = (pageHeight / PT_PER_MM - MARGIN_MM - contentH) * PT_PER_MM
  page.pushOperators(pushGraphicsState(), rectangle(clipX, clipY, contentW * PT_PER_MM, contentH * PT_PER_MM), clip(), endPath())
  for (const piece of pieces) {
    if (!pieceHitsCell(piece, windowX, windowY, contentW, contentH)) continue
    const pathOriginX = (originXmm(piece.placeX, windowX) - piece.minX) * PT_PER_MM
    const pathOriginY = pageHeight - (originYmm(piece.placeY, windowY) - piece.minY) * PT_PER_MM
    for (const path of piece.paths) {
      page.drawSvgPath(path.d, {
        x: pathOriginX,
        y: pathOriginY,
        scale: PT_PER_MM,
        borderColor: BLACK,
        borderWidth: 0.6,
      })
    }
  }
  const bounds = {
    x: clipX + 3,
    y: clipY + 3,
    w: contentW * PT_PER_MM - 6,
    h: contentH * PT_PER_MM - 6,
  }
  const layout = layoutPageLabels(font, locale, pieces, cell, contentW, contentH, pageHeight, bounds)
  for (const box of layout.boxes) {
    page.drawText(box.text, { x: box.x, y: box.y, size: box.size, font, color: BLACK })
  }
  page.pushOperators(popGraphicsState())
  page.drawText(`${cell.id}  ${labels.page} ${index} ${labels.of} ${gridSize}`, {
    x: MARGIN_MM * PT_PER_MM,
    y: 8,
    size: 9,
    font,
    color: BLACK,
  })
}

/** Overlapping or clipped label boxes, used by the export tests. */
export async function labelIssues(pieces, paper, locale = 'en') {
  const size = PAPER_MM[paper]
  const doc = await PDFDocument.create()
  doc.registerFontkit(fontkit)
  const fontBytes = readFileSync(
    join(fontDirectory, locale === 'ja' ? 'KosugiMaru-Regular.woff' : 'NotoSans-Regular.ttf')
  )
  const font = await doc.embedFont(fontBytes, { subset: true })
  const placed = layoutPieces(pieces, paper)
  const pageHeight = size.height * PT_PER_MM
  const issues = []
  for (const cell of patternCells(placed)) {
    if (cell.blank) continue
    const clipX = MARGIN_MM * PT_PER_MM
    const clipY = (pageHeight / PT_PER_MM - MARGIN_MM - placed.contentH) * PT_PER_MM
    const bounds = {
      x: clipX + 3,
      y: clipY + 3,
      w: placed.contentW * PT_PER_MM - 6,
      h: placed.contentH * PT_PER_MM - 6,
    }
    const layout = layoutPageLabels(font, locale, placed.pieces, cell, placed.contentW, placed.contentH, pageHeight, bounds)
    for (const issue of layout.issues) issues.push(`${cell.id} ${issue}`)
  }
  return issues
}

function drawAssemblyPage(page, context) {
  const { font, labels, grid, cols, pageWidth, pageHeight } = context
  page.drawText(labels.assembly, {
    x: MARGIN_MM * PT_PER_MM,
    y: pageHeight - MARGIN_MM * PT_PER_MM - 14,
    size: 16,
    font,
    color: BLACK,
  })
  page.drawText(labels.pageGrid, {
    x: MARGIN_MM * PT_PER_MM,
    y: pageHeight - MARGIN_MM * PT_PER_MM - 32,
    size: 11,
    font,
    color: BLACK,
  })
  const cell = 28
  grid.forEach((entry, index) => {
    const col = index % cols
    const row = Math.floor(index / cols)
    const x = MARGIN_MM * PT_PER_MM + col * (cell + 8)
    const y = pageHeight - 80 - row * (cell + 8) - cell
    page.drawRectangle({ x, y, width: cell, height: cell, borderWidth: 1, borderColor: BLACK })
    page.drawText(entry.id, { x: x + 6, y: y + 10, size: 9, font, color: BLACK })
  })
  void pageWidth
}

function pieceHitsCell(piece, windowX, windowY, contentW, contentH) {
  return piece.placeX < windowX + contentW && piece.placeX + piece.width > windowX
    && piece.placeY < windowY + contentH && piece.placeY + piece.height > windowY
}

function cellHasContent(pieces, cell, contentW, contentH) {
  const windowX = cell.col * contentW
  const windowY = cell.row * contentH
  const right = windowX + contentW
  const bottom = windowY + contentH
  for (const piece of pieces) {
    for (const path of piece.paths) {
      for (const segment of path.geometry?.segments || []) {
        const x1 = piece.placeX + (segment.x1 - piece.minX)
        const y1 = piece.placeY + (segment.y1 - piece.minY)
        const x2 = piece.placeX + (segment.x2 - piece.minX)
        const y2 = piece.placeY + (segment.y2 - piece.minY)
        if (segment.length < 0.4) continue
        if (segmentHitsRect(x1, y1, x2, y2, windowX, windowY, right, bottom)) return true
      }
    }
  }
  return false
}

function segmentHitsRect(x1, y1, x2, y2, left, top, right, bottom) {
  const inside = (x, y) => x >= left && x <= right && y >= top && y <= bottom
  if (inside(x1, y1) || inside(x2, y2)) return true
  const edges = [
    [left, top, right, top],
    [right, top, right, bottom],
    [right, bottom, left, bottom],
    [left, bottom, left, top],
  ]
  return edges.some(([ax, ay, bx, by]) => segmentsCross(x1, y1, x2, y2, ax, ay, bx, by))
}

function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy) {
  const abx = bx - ax
  const aby = by - ay
  const cdx = dx - cx
  const cdy = dy - cy
  const denom = abx * cdy - aby * cdx
  if (Math.abs(denom) < 1e-9) return false
  const t = ((cx - ax) * cdy - (cy - ay) * cdx) / denom
  const u = ((cx - ax) * aby - (cy - ay) * abx) / denom
  return t >= 0 && t <= 1 && u >= 0 && u <= 1
}

function layoutPageLabels(font, locale, pieces, cell, contentW, contentH, pageHeight, bounds) {
  const windowX = cell.col * contentW
  const windowY = cell.row * contentH
  const planned = []
  const marks = []
  for (const piece of pieces) {
    if (!pieceHitsCell(piece, windowX, windowY, contentW, contentH)) continue
    for (const path of piece.paths) {
      if (!String(path.className || '').includes('sewlens-mark')) continue
      for (const segment of path.geometry?.segments || []) {
        const start = canvasPoint(piece, segment.x1, segment.y1)
        const end = canvasPoint(piece, segment.x2, segment.y2)
        if (!segmentHitsRect(start.x, start.y, end.x, end.y, windowX, windowY, windowX + contentW, windowY + contentH)) continue
        const a = toPage(start.x, start.y, windowX, windowY, pageHeight)
        const b = toPage(end.x, end.y, windowX, windowY, pageHeight)
        marks.push({ x1: a.x, y1: a.y, x2: b.x, y2: b.y })
      }
    }
    const spot = nameSpot(piece, windowX, windowY, contentW, contentH)
    planned.push({
      text: pieceLabel(locale, piece.name),
      size: 8,
      ...toPage(spot.x, spot.y, windowX, windowY, pageHeight),
    })
    for (const path of piece.paths) {
      if (!path.label) continue
      const anchor = labelAnchor(piece, path, windowX, windowY, contentW, contentH, pageHeight)
      if (anchor) planned.push({ text: path.label, size: 7, ...anchor })
    }
  }
  return placeLabels(font, planned, marks, bounds)
}

function canvasPoint(piece, x, y) {
  return {
    x: piece.placeX + (x - piece.minX),
    y: piece.placeY + (y - piece.minY),
  }
}

function nameSpot(piece, windowX, windowY, contentW, contentH) {
  const left = Math.max(piece.placeX, windowX)
  const top = Math.max(piece.placeY, windowY)
  const right = Math.min(piece.placeX + piece.width, windowX + contentW)
  const bottom = Math.min(piece.placeY + piece.height, windowY + contentH)
  return {
    x: left + Math.min(8, Math.max(2, (right - left) * 0.12)),
    y: top + Math.min(12, Math.max(4, (bottom - top) * 0.16)),
  }
}

function labelAnchor(piece, path, windowX, windowY, contentW, contentH, pageHeight) {
  let best = null
  for (const segment of path.geometry?.segments || []) {
    if (segment.length < 8) continue
    const start = canvasPoint(piece, segment.x1, segment.y1)
    const end = canvasPoint(piece, segment.x2, segment.y2)
    if (!segmentHitsRect(start.x, start.y, end.x, end.y, windowX, windowY, windowX + contentW, windowY + contentH)) continue
    if (!best || segment.length > best.length) best = { ...segment, start, end }
  }
  if (!best) return null
  const along = 0.72
  const x = best.start.x + (best.end.x - best.start.x) * along
  const y = best.start.y + (best.end.y - best.start.y) * along
  const dx = best.end.x - best.start.x
  const dy = best.end.y - best.start.y
  const length = Math.hypot(dx, dy) || 1
  return toPage(x + (-dy / length) * 6, y + (dx / length) * 6, windowX, windowY, pageHeight)
}

function textBox(font, text, x, y, size) {
  return { text, x, y, w: font.widthOfTextAtSize(text, size), h: size + 1.5, size }
}

function boxesOverlap(a, b, pad = 1.25) {
  return a.x < b.x + b.w + pad && a.x + a.w + pad > b.x && a.y < b.y + b.h + pad && a.y + a.h + pad > b.y
}

function boxHitsSegment(box, segment, pad = 2) {
  return segmentHitsRect(
    segment.x1,
    segment.y1,
    segment.x2,
    segment.y2,
    box.x - pad,
    box.y - pad,
    box.x + box.w + pad,
    box.y + box.h + pad,
  )
}

function placeLabels(font, planned, marks, bounds) {
  const boxes = []
  const issues = []
  for (const item of planned) {
    const shifts = []
    for (const dy of [0, 12, -12, 24, -24, 36, -36, 48, 60]) {
      for (const dx of [0, 16, -16, 32, -32, 48, -48, 64]) shifts.push([dx, dy])
    }
    let chosen = null
    const fits = (box) => box.x >= bounds.x
      && box.y >= bounds.y
      && box.x + box.w <= bounds.x + bounds.w
      && box.y + box.h <= bounds.y + bounds.h
      && !boxes.some((other) => boxesOverlap(box, other))
      && !marks.some((segment) => boxHitsSegment(box, segment))
    for (const [dx, dy] of shifts) {
      const box = textBox(font, item.text, item.x + dx, item.y + dy, item.size)
      if (fits(box)) {
        chosen = box
        break
      }
    }
    if (!chosen) {
      const step = 9
      search: for (let y = bounds.y; y + item.size + 2 <= bounds.y + bounds.h; y += step) {
        for (let x = bounds.x; x + 12 <= bounds.x + bounds.w; x += step) {
          const box = textBox(font, item.text, x, y, item.size)
          if (!fits(box)) continue
          chosen = box
          break search
        }
      }
    }
    if (!chosen) {
      issues.push(`no clear spot for “${item.text}”`)
      continue
    }
    boxes.push(chosen)
  }
  return { boxes, issues }
}

function originXmm(placeX, windowX) {
  return MARGIN_MM + placeX - windowX
}

function originYmm(placeY, windowY) {
  return MARGIN_MM + placeY - windowY
}

function toPage(canvasX, canvasY, windowX, windowY, pageHeightPt) {
  const xMm = MARGIN_MM + (canvasX - windowX)
  const yMmFromTop = MARGIN_MM + (canvasY - windowY)
  return {
    x: xMm * PT_PER_MM,
    y: pageHeightPt - yMmFromTop * PT_PER_MM,
  }
}
