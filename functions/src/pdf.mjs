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
  const contentW = size.width - MARGIN_MM * 2
  const contentH = size.height - MARGIN_MM * 2 - 8

  const placed = placePieces(pieces, contentW)
  const rows = Math.max(1, Math.ceil(placed.canvasHeight / contentH))
  const cols = Math.max(1, Math.ceil(placed.canvasWidth / contentW))
  const grid = []
  for (let row = 0; row < rows; row += 1) {
    for (let col = 0; col < cols; col += 1) grid.push({ row, col, id: `${String.fromCharCode(65 + row)}${col + 1}` })
  }

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

  for (const cell of grid) {
    const page = doc.addPage([pageWidth, pageHeight])
    drawPatternPage(page, {
      font,
      locale,
      pieces: placed.pieces,
      cell,
      contentW,
      contentH,
      pageWidth,
      pageHeight,
      labels,
      gridSize: grid.length,
      index: grid.indexOf(cell) + 1,
    })
  }

  drawAssemblyPage(doc.addPage([pageWidth, pageHeight]), {
    font,
    labels,
    grid,
    cols,
    pageWidth,
    pageHeight,
  })

  return doc.save()
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
  return {
    pieces: placedPieces,
    canvasWidth: Math.max(contentW, x),
    canvasHeight: y + rowHeight,
  }
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

function drawPatternPage(page, context) {
  const { font, locale, pieces, cell, contentW, contentH, pageWidth, pageHeight, labels, gridSize, index } = context
  const originX = MARGIN_MM
  const originTop = MARGIN_MM
  const windowX = cell.col * contentW
  const windowY = cell.row * contentH
  const clipX = originX * PT_PER_MM
  const clipY = (pageHeight / PT_PER_MM - originTop - contentH) * PT_PER_MM
  page.pushOperators(pushGraphicsState(), rectangle(clipX, clipY, contentW * PT_PER_MM, contentH * PT_PER_MM), clip(), endPath())
  for (const piece of pieces) {
    const originX = (originXmm(piece.placeX, windowX) - piece.minX) * PT_PER_MM
    const originY = pageHeight - (originYmm(piece.placeY, windowY) - piece.minY) * PT_PER_MM
    for (const path of piece.paths) {
      page.drawSvgPath(path.d, {
        x: originX,
        y: originY,
        scale: PT_PER_MM,
        borderColor: BLACK,
        borderWidth: 0.6,
      })
    }
    const labelPoint = toPage(piece.placeX, piece.placeY, windowX, windowY, pageHeight)
    if (labelPoint.x > 0 && labelPoint.y > 0 && labelPoint.x < pageWidth && labelPoint.y < pageHeight) {
      page.drawText(pieceLabel(locale, piece.name), {
        x: Math.max(clipX, labelPoint.x),
        y: Math.min(pageHeight - 10, labelPoint.y),
        size: 8,
        font,
        color: BLACK,
      })
    }
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
