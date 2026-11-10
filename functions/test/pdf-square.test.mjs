import { inflateSync } from 'node:zlib'
import { PDFDocument, PDFName } from 'pdf-lib'
import { draftPattern } from '../src/draft-pattern.mjs'
import { uiLabels } from '../src/labels.mjs'
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
    text += decodePage(pageStreams(doc, page), fontMaps(doc, page))
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
