import { inflateSync } from 'node:zlib'
import { PDFDocument, PDFName } from 'pdf-lib'
import { draftPattern } from '../src/draft-pattern.mjs'
import { patternPieces } from '../src/geometry.mjs'
import { cutCountPhrase, markLabel, uiLabels } from '../src/labels.mjs'
import { labelIssues, layoutPieces, patternGrid } from '../src/pdf.mjs'
import { PT_PER_IN, PT_PER_MM } from '../src/units.mjs'

function inflate(stream) {
  const bytes = Buffer.from(stream.getContents())
  try {
    return inflateSync(bytes)
  } catch {
    return bytes
  }
}

function pageStreams(doc, page) {
  const contents = page.node.Contents()
  const looked = doc.context.lookup(contents)
  const refs = typeof looked?.size === 'function' ? Array.from({ length: looked.size() }, (_, index) => looked.get(index)) : [contents]
  return refs.map((ref) => inflate(doc.context.lookup(ref)).toString('latin1')).join('\n')
}

function parseCmap(text) {
  const map = new Map()
  const remember = (glyph, hex) => {
    const key = glyph.toUpperCase().padStart(4, '0')
    let value = ''
    const bytes = Buffer.from(hex, 'hex')
    for (let index = 0; index < bytes.length; index += 2) {
      value += String.fromCharCode((bytes[index] << 8) | bytes[index + 1])
    }
    map.set(key, value)
  }
  for (const block of text.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) {
    for (const pair of block[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g)) remember(pair[1], pair[2])
  }
  for (const block of text.matchAll(/beginbfrange([\s\S]*?)endbfrange/g)) {
    for (const range of block[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g)) {
      const start = Number.parseInt(range[1], 16)
      const end = Number.parseInt(range[2], 16)
      let code = Number.parseInt(range[3], 16)
      for (let glyph = start; glyph <= end; glyph += 1) {
        remember(glyph.toString(16), code.toString(16).padStart(4, '0'))
        code += 1
      }
    }
  }
  return map
}

function fontMaps(doc, page) {
  const maps = new Map()
  const fonts = page.node.Resources()?.lookup(PDFName.of('Font'))
  if (!fonts?.entries) return maps
  for (const [name, ref] of fonts.entries()) {
    const font = doc.context.lookup(ref)
    const toUnicode = font.lookup?.(PDFName.of('ToUnicode'))
    if (!toUnicode) continue
    const key = String(name).replace(/^\//, '')
    maps.set(key, parseCmap(inflate(doc.context.lookup(toUnicode)).toString('latin1')))
  }
  return maps
}

function decodePage(content, maps) {
  let current = null
  let text = ''
  for (const match of content.matchAll(/\/([^\s]+)\s+[0-9.]+\s+Tf|<([0-9A-Fa-f]+)>\s*Tj/g)) {
    if (match[1]) current = maps.get(match[1]) || null
    else if (match[2] && current) {
      if (text && !text.endsWith('\n')) text += '\n'
      for (let index = 0; index < match[2].length; index += 4) {
        text += current.get(match[2].slice(index, index + 4).toUpperCase()) || ''
      }
    }
  }
  return text
}

async function openPdf(pdfBase64) {
  return PDFDocument.load(Buffer.from(pdfBase64, 'base64'))
}

async function rectangles(pdfBase64) {
  const doc = await openPdf(pdfBase64)
  const raw = pageStreams(doc, doc.getPage(0))
  return [...raw.matchAll(/(-?[0-9.]+) (-?[0-9.]+) m\n(-?[0-9.]+) (-?[0-9.]+) l\n(-?[0-9.]+) (-?[0-9.]+) l\n(-?[0-9.]+) (-?[0-9.]+) l/g)].map((match) => ({
    w: Math.abs(Number(match[5]) - Number(match[1])),
    h: Math.abs(Number(match[4]) - Number(match[2])),
  }))
}

async function pdfText(pdfBase64) {
  const doc = await openPdf(pdfBase64)
  let text = ''
  for (const page of doc.getPages()) {
    text += `${decodePage(pageStreams(doc, page), fontMaps(doc, page))}\n`
  }
  return text
}

const measurements = {
  chest: 96,
  waist: 82,
  hips: 98,
  neck: 38,
  shoulderSlope: 13,
  hpsToWaistBack: 45,
  shoulderToShoulder: 42,
  shoulderToWrist: 62,
  biceps: 32,
  wrist: 17,
}

describe('tiled PDF test square', () => {
  test.each(['letter', 'a4'])('%s test square is 100.0 mm and 4.000 in', async (paper) => {
    const result = await draftPattern({
      design: 'brian',
      measurements,
      units: 'metric',
      locale: 'en',
      paper,
    })
    const rects = await rectangles(result.pdfBase64)
    const metric = rects.find((rect) => Math.abs(rect.w / PT_PER_MM - 100) < 0.05 && Math.abs(rect.h / PT_PER_MM - 100) < 0.05)
    const imperial = rects.find((rect) => Math.abs(rect.w / PT_PER_IN - 4) < 0.001 && Math.abs(rect.h / PT_PER_IN - 4) < 0.001)
    expect(metric).toBeTruthy()
    expect(imperial).toBeTruthy()
    expect((metric.w / PT_PER_MM).toFixed(1)).toBe('100.0')
    expect((metric.h / PT_PER_MM).toFixed(1)).toBe('100.0')
    expect((imperial.w / PT_PER_IN).toFixed(3)).toBe('4.000')
    expect((imperial.h / PT_PER_IN).toFixed(3)).toBe('4.000')
    expect(result.yardage.map((row) => row.fabricCm)).toEqual([112, 150])
    expect(result.yardage.map((row) => row.fabricIn)).toEqual([45, 60])
    expect(result.yardage[0].lengthMm).toBeGreaterThanOrEqual(result.yardage[1].lengthMm)
  })

  test('labels for all eight languages are in the PDF', async () => {
    const locales = ['en', 'de', 'fr', 'es', 'pt-BR', 'ja', 'it', 'nl']
    for (const locale of locales) {
      const result = await draftPattern({
        design: 'trayvon',
        measurements,
        units: 'metric',
        locale,
        paper: locale === 'en' ? 'letter' : 'a4',
      })
      const labels = uiLabels(locale)
      const text = await pdfText(result.pdfBase64)
      for (const phrase of [labels.legend, labels.assembly, labels.testSquareMetric, labels.pageGrid]) {
        if (!text.includes(phrase)) throw new Error(`${locale} PDF is missing “${phrase}”`)
      }
      for (const label of result.labels.pieces.map((piece) => piece.label)) {
        if (!text.includes(label)) throw new Error(`${locale} PDF is missing “${label}”`)
      }
      expect(text).not.toContain('{{missing:')
    }
  })
})

const GARMENTS = {
  aaron: {
    biceps: 32,
    chest: 96,
    hpsToBust: 27,
    hpsToWaistBack: 45,
    neck: 38,
    shoulderToShoulder: 42,
    shoulderSlope: 13,
    waistToArmpit: 21,
    waistToHips: 14,
    hips: 98,
  },
  teagan: {
    biceps: 32,
    chest: 96,
    hpsToBust: 27,
    hpsToWaistBack: 45,
    neck: 38,
    shoulderToShoulder: 42,
    shoulderSlope: 13,
    waistToArmpit: 21,
    waistToHips: 14,
    hips: 98,
    waist: 82,
    shoulderToWrist: 62,
    wrist: 17,
  },
  penelope: {
    waist: 82,
    seat: 100,
    waistToHips: 14,
    waistToSeat: 22,
    waistToKnee: 56,
  },
}

function spanText(svg) {
  return [...svg.matchAll(/<tspan[^>]*>([^<]*)<\/tspan>/g)].map((match) => match[1])
}

const KEYISH = /\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b[A-Za-z][A-Za-z0-9-]*:[A-Za-z0-9_.-]+/
const BRANDING = /FreeSewing|ephemeral|patron|\bv\d+\.\d+\.\d+\b|\b20\d{2}\b/i

function assertCleanText(text, design) {
  const key = text.match(KEYISH)
  if (key) throw new Error(`${design} still has a raw key “${key[0]}”`)
  const brand = text.match(BRANDING)
  if (brand) throw new Error(`${design} still has “${brand[0]}”`)
}

describe('tiled pattern pages cover every piece', () => {
  test.each(['aaron', 'teagan', 'penelope'].flatMap((design) => ['a4', 'letter'].map((paper) => [design, paper])))(
    '%s on %s keeps every piece inside the page grid',
    async (design, paper) => {
      const result = await draftPattern({
        design,
        measurements: GARMENTS[design],
        units: 'metric',
        locale: 'en',
        paper,
      })
      const pieces = patternPieces(result.svg)
      expect(pieces.length).toBeGreaterThan(0)
      const layout = layoutPieces(pieces, paper)
      for (const piece of layout.pieces) {
        expect(piece.placeX + piece.width).toBeLessThanOrEqual(layout.cols * layout.contentW + 0.05)
        expect(piece.placeY + piece.height).toBeLessThanOrEqual(layout.rows * layout.contentH + 0.05)
      }
      const widest = Math.max(...pieces.map((piece) => piece.width))
      expect(layout.cols * layout.contentW).toBeGreaterThanOrEqual(widest - 0.05)
      const doc = await openPdf(result.pdfBase64)
      const grid = patternGrid(pieces, paper)
      expect(doc.getPageCount()).toBe(grid.printed.length + 2)
      expect(grid.printed.length).toBeGreaterThan(0)
      const text = await pdfText(result.pdfBase64)
      for (const cell of grid.cells) expect(text).toContain(cell.id)
      expect(text).toContain(`A${layout.cols}`)
      expect(await labelIssues(pieces, paper, 'en')).toEqual([])
      const rects = await rectangles(result.pdfBase64)
      const metric = rects.find((rect) => Math.abs(rect.w / PT_PER_MM - 100) < 0.05 && Math.abs(rect.h / PT_PER_MM - 100) < 0.05)
      const imperial = rects.find((rect) => Math.abs(rect.w / PT_PER_IN - 4) < 0.001 && Math.abs(rect.h / PT_PER_IN - 4) < 0.001)
      expect((metric.w / PT_PER_MM).toFixed(1)).toBe('100.0')
      expect((imperial.w / PT_PER_IN).toFixed(3)).toBe('4.000')
      const style = result.svg.match(/<style type="text\/css">[\s\S]*?<\/style>/)
      expect(style).toBeTruthy()
      expect(style[0]).toMatch(/fill:\s*none/)
      expect(style[0].length).toBeGreaterThan(200)
      expect(result.svg).toMatch(/\.note:not\(\.sewlens-mark\)/)
      expect(result.svg).toMatch(/\.help:not\(\.sewlens-mark\)/)
      expect(result.svg).toMatch(/\.hidden[\s\S]{0,160}display:\s*none/)
      expect(result.svg).toMatch(/\.sewlens-mark[\s\S]{0,160}stroke:\s*#212121/)
      const marks = result.svg.match(/<path\b[^>]*class="[^"]*\bsewlens-mark\b[^"]*"[^>]*\/>/g) || []
      expect(marks.length).toBeGreaterThan(0)
      for (const path of marks) {
        expect(path).not.toMatch(/display:\s*none/)
        const className = (/class="([^"]*)"/.exec(path)?.[1] || '').split(/\s+/)
        expect(className).not.toContain('note')
        expect(className).not.toContain('help')
      }
      for (const path of result.svg.match(/<path\b[^>]*class="[^"]*\bfabric\b[^"]*"[^>]*\/>/g) || []) {
        expect(path).toMatch(/fill="none"/)
        expect(path).not.toMatch(/fill="(?:#000(?:000)?|black)"/i)
      }
      for (const piece of pieces) {
        let longest = 0
        const grain = piece.paths.some((path) => path.grain && !path.fold && path.geometry.segments.some((segment) => {
          longest = Math.max(longest, segment.length)
          return segment.length > 12
        }))
        for (const path of piece.paths) {
          if (!path.className.includes('sewlens-mark')) continue
          for (const segment of path.geometry.segments) longest = Math.max(longest, segment.length)
        }
        expect(longest).toBeGreaterThan(12)
        expect(grain).toBe(true)
        expect(piece.cutCount).toMatch(/\d/)
        expect(text).toContain(piece.cutCount)
        const at = result.svg.indexOf(`id="fs-stack-${piece.name}-part-${piece.name}"`)
        const nextAt = result.svg.indexOf('id="fs-stack-', at + 12)
        const inner = result.svg.slice(at, nextAt === -1 ? undefined : nextAt)
        expect(inner).toMatch(/Cut \d|data-sewlens-cut="1"/)
      }
      const labels = spanText(result.svg).join('\n')
      assertCleanText(labels, design)
      assertCleanText(text, design)
      expect(labels).toContain('Front')
      expect(labels).toContain('Back')
      expect(labels).toMatch(/Cut \d/)
      expect(labels).toMatch(/Grainline|Cut on fold/)
      expect(text).toMatch(/Grainline|Cut on fold/)
      if (design === 'teagan') {
        expect(labels).toContain('Sleeve')
        expect(result.svg).toContain('sewlens-mark')
        expect(result.svg).not.toMatch(/xlink:href="#notch"/)
      }
      if (design === 'penelope') {
        const front = pieces.find((piece) => piece.name.toLowerCase().includes('front'))
        const at = result.svg.indexOf(`id="fs-stack-${front.name}-part-${front.name}"`)
        const inner = result.svg.slice(at, result.svg.indexOf('id="fs-stack-', at + 12))
        expect(inner).toContain('Cut 1 on the fold')
      }
      if (design === 'aaron') {
        const folds = spanText(result.svg).filter((line) => line.trim() === 'Fold here')
        const foldPaths = (result.svg.match(/data-sewlens-fold="1"/g) || []).length
        const foldYs = [...result.svg.matchAll(/class="sewlens-fold-label"[^>]*>\s*<tspan[^>]*y="([^"]+)"/g)].map((match) => Math.round(Number(match[1])))
        expect(foldPaths).toBeGreaterThan(0)
        expect(folds).toHaveLength(foldPaths)
        expect(new Set(foldYs).size).toBeGreaterThan(1)
        expect(result.svg).not.toContain('Fold here Fold here')
        expect(text.split('Fold here').length - 1).toBe(foldPaths)
      }
    },
    60000
  )

  test('fold and grainline text is translated in every locale', async () => {
    for (const locale of ['en', 'de', 'fr', 'es', 'pt-BR', 'ja', 'it', 'nl']) {
      const result = await draftPattern({
        design: 'aaron',
        measurements: GARMENTS.aaron,
        units: 'metric',
        locale,
        paper: 'a4',
        pdf: false,
      })
      const labels = spanText(result.svg).join('\n')
      expect(labels).toContain(uiLabels(locale).grainline)
      expect(labels).toContain(uiLabels(locale).cutOnFold)
      expect(labels).toContain(markLabel(locale, 'foldHere'))
      assertCleanText(labels, `aaron ${locale}`)
      const skirt = await draftPattern({
        design: 'penelope',
        measurements: GARMENTS.penelope,
        units: 'metric',
        locale,
        paper: 'a4',
        pdf: false,
      })
      const skirtText = spanText(skirt.svg).join('\n')
      expect(skirtText).toContain(cutCountPhrase(locale, { cut: 1, onFold: true }))
      assertCleanText(skirtText, `penelope ${locale}`)
    }
  }, 180000)
})
