/**
 * Marketing export harness.
 *
 * Calls the app's draftPattern() (functions/src/draft-pattern.mjs), which
 * drafts with FreeSewing, lays the pieces out, and builds the tiled PDF
 * through renderPatternPdf(). This file does not reimplement either step.
 *
 * Run from the repo root, after `npm ci` inside functions/:
 *   node tools/marketing_export_harness/export.mjs
 *
 * Raster tools used only to turn those outputs into PNG:
 *   pdftoppm  — pages of the PDF bytes draftPattern returned
 *   rsvg-convert — the SVG string draftPattern returned
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { draftPattern } from '../../functions/src/draft-pattern.mjs'
import { DESIGNS } from '../../functions/src/designs.mjs'
import { patternPieces } from '../../functions/src/geometry.mjs'
import { PAPER_MM, PT_PER_IN, PT_PER_MM } from '../../functions/src/units.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '../..')
const outRoot = join(root, 'tools/marketing_export_harness/out')
const artifactRoot = '/opt/cursor/artifacts/sewlens-real-patterns'

/** Same three finished garments, different design ids. */
const DESIGNS_TO_EXPORT = ['aaron', 'teagan', 'penelope']

/**
 * Stroke used when rasterizing the untiled SVG.
 * pdf.mjs strokes the same paths at 0.6pt (about 0.21mm). At a 2000px
 * render that hairline disappears, so the PNG uses a heavier stroke in the
 * SVG's own millimetre units. Geometry is unchanged.
 */
const ASSEMBLED_STROKE_MM = 0.65
const ASSEMBLED_LONG_SIDE = 2000
const PAGE_DPI = 170

const VISIBILITY_CSS = `<style type="text/css"><![CDATA[
.hidden, .note, text, use { display: none !important; }
path, circle, ellipse, line, polyline, polygon, rect {
  fill: none !important;
  stroke: #000000 !important;
  stroke-width: ${ASSEMBLED_STROKE_MM} !important;
  stroke-linecap: round;
  stroke-linejoin: round;
}
]]></style>`

function testBodyCentimetres() {
  const source = readFileSync(join(root, 'functions/test/dimensions.test.mjs'), 'utf8')
  const match = source.match(/const BASE_MM = \{([\s\S]*?)\n\}/)
  if (!match) throw new Error('BASE_MM was not found in functions/test/dimensions.test.mjs')
  const baseMm = Function(`"use strict"; return ({${match[1]}});`)()
  const centimetres = {}
  for (const [key, value] of Object.entries(baseMm)) {
    // measurementsFor(1) in that test file: degrees stay, lengths become cm.
    centimetres[key] = key === 'shoulderSlope' ? value : Math.round(value) / 10
  }
  return centimetres
}

function measurementsForDesign(design, body) {
  const needed = [...DESIGNS[design].patternConfig.measurements]
  const measurements = {}
  for (const key of needed) {
    if (!(key in body)) throw new Error(`${design} needs ${key}, which is not in BASE_MM`)
    measurements[key] = body[key]
  }
  return measurements
}

function viewBoxSize(svg) {
  const match = svg.match(/viewBox="\s*[\d.+-]+\s+[\d.+-]+\s+([\d.]+)\s+([\d.]+)\s*"/)
  if (!match) throw new Error('SVG has no viewBox')
  return { width: Number(match[1]), height: Number(match[2]) }
}

function styledForRaster(svg) {
  if (!/<style type="text\/css">[\s\S]*?<\/style>/.test(svg)) {
    throw new Error('draft SVG has no style block to replace')
  }
  return svg.replace(/<style type="text\/css">[\s\S]*?<\/style>/, VISIBILITY_CSS)
}

function run(cmd, args) {
  execFileSync(cmd, args, { stdio: 'inherit' })
}

function compositeOnWhite(src, dest) {
  execFileSync('python3', ['-c', `
from PIL import Image
im = Image.open(${JSON.stringify(src)}).convert("RGBA")
bg = Image.new("RGB", im.size, (255, 255, 255))
bg.paste(im, mask=im.getchannel("A"))
ink = 0
step = max(1, (im.size[0] * im.size[1]) // 400000)
pixels = bg.getdata()
for i in range(0, len(pixels), step):
    r, g, b = pixels[i]
    if r < 250 or g < 250 or b < 250:
        ink += 1
frac = ink / max(1, len(range(0, len(pixels), step)))
if not (0.002 < frac < 0.45):
    raise SystemExit(f"assembled raster ink fraction {frac:.4f} looks empty or solid")
bg.save(${JSON.stringify(dest)}, "PNG")
print(f"assembled {bg.size[0]}x{bg.size[1]} ink {frac:.3f}")
`])
}

/**
 * Page 1 is the calibration page. Crop the two test squares and their
 * captions. Positions follow drawCalibrationPage in functions/src/pdf.mjs:
 * 12mm margin, 100mm square, 18pt gap, then a 4in square.
 */
function cropTestSquare(pagePng, dest, paper) {
  const size = PAPER_MM[paper]
  const marginMm = 12
  const metricMm = 100
  const gapMm = (18 * 25.4) / 72
  const imperialMm = (4 * PT_PER_IN) / PT_PER_MM
  const labelMm = (14 * 25.4) / 72
  // Stop before the legend column. drawCalibrationPage places that text
  // 16pt to the right of the imperial square.
  const legendGapMm = (16 * 25.4) / 72
  const x0 = 4
  const y0 = 4
  const x1 = marginMm + Math.max(metricMm, imperialMm) + legendGapMm - 1
  const y1 = marginMm + metricMm + gapMm + imperialMm + labelMm + 8
  execFileSync('python3', ['-c', `
from PIL import Image
im = Image.open(${JSON.stringify(pagePng)})
w, h = im.size
paper_w = ${size.width}
paper_h = ${size.height}
def px(mm, span, paper):
    return int(round(mm / paper * span))
box = (px(${x0}, w, paper_w), px(${y0}, h, paper_h), px(${x1}, w, paper_w), px(${y1}, h, paper_h))
crop = im.crop(box)
if crop.getbbox() is None:
    raise SystemExit("test square crop is empty")
crop.save(${JSON.stringify(dest)}, "PNG")
print("test-square", crop.size, "from", box)
`])
}

async function exportDesign(design, body) {
  const measurements = measurementsForDesign(design, body)
  const result = await draftPattern({
    design,
    measurements,
    units: 'metric',
    locale: 'en',
  })
  if (result.paper !== 'a4') {
    throw new Error(`${design} paper default was ${result.paper}, expected a4 for locale en + metric`)
  }
  const pdfBytes = Buffer.from(result.pdfBase64, 'base64')
  if (!pdfBytes.subarray(0, 5).toString('latin1').startsWith('%PDF')) {
    throw new Error(`${design} pdfBase64 is not a PDF`)
  }
  const dir = join(outRoot, design)
  mkdirSync(dir, { recursive: true })
  const pdfPath = join(dir, 'pattern-tiled.pdf')
  writeFileSync(pdfPath, pdfBytes)
  writeFileSync(join(dir, 'pattern.svg'), result.svg)
  const info = execFileSync('pdfinfo', [pdfPath], { encoding: 'utf8' })
  const pageCount = Number(info.match(/Pages:\s+(\d+)/)?.[1])
  if (!pageCount || pageCount < 3) throw new Error(`${design} PDF has ${pageCount} pages`)

  const tmp = join(dir, '.tmp')
  mkdirSync(tmp, { recursive: true })
  run('pdftoppm', ['-png', '-r', String(PAGE_DPI), '-f', '1', '-l', '1', pdfPath, join(tmp, 'page')])
  const rendered = readdirSync(tmp).filter((name) => name.startsWith('page-') && name.endsWith('.png'))
  if (rendered.length !== 1) throw new Error(`${design} page raster: ${rendered.join(', ')}`)
  const page1 = join(tmp, rendered[0])
  writeFileSync(join(dir, 'page-1.png'), readFileSync(page1))
  cropTestSquare(page1, join(dir, 'test-square.png'), result.paper)

  const box = viewBoxSize(result.svg)
  const styled = styledForRaster(result.svg)
  const styledPath = join(tmp, 'assembled.svg')
  writeFileSync(styledPath, styled)
  const rawPng = join(tmp, 'assembled-raw.png')
  const rasterArgs = box.width >= box.height
    ? ['-w', String(ASSEMBLED_LONG_SIDE)]
    : ['-h', String(ASSEMBLED_LONG_SIDE)]
  run('rsvg-convert', [...rasterArgs, styledPath, '-o', rawPng])
  compositeOnWhite(rawPng, join(dir, 'assembled.png'))

  const text = execFileSync('pdftotext', ['-f', '1', '-l', '1', '-layout', pdfPath, '-'], { encoding: 'utf8' })
  if (!text.includes('10 cm test square') || !text.includes('4 in test square')) {
    throw new Error(`${design} page 1 is missing the test square captions`)
  }

  const pieces = patternPieces(result.svg).map((piece) => ({
    id: piece.name,
    label: result.labels.pieces.find((entry) => entry.id === piece.name)?.label || piece.name,
    widthMm: Math.round(piece.width * 10) / 10,
    heightMm: Math.round(piece.height * 10) / 10,
  }))
  const contentWidthMm = PAPER_MM[result.paper].width - 24
  const manifest = {
    design: result.design,
    displayName: result.labels.design,
    locale: result.locale,
    units: result.units,
    paper: result.paper,
    seamAllowanceMm: result.seamAllowanceMm,
    measurements: measurements,
    measurementSource: 'functions/test/dimensions.test.mjs BASE_MM, measurementsFor(1), only the design required keys',
    pieces,
    pdfPages: pageCount,
    contentWidthMm,
    piecesWiderThanContent: pieces.filter((piece) => piece.widthMm > contentWidthMm).map((piece) => piece.id),
    viewBoxMm: box,
    called: [
      'functions/src/draft-pattern.mjs draftPattern',
      'functions/src/pdf.mjs renderPatternPdf (via draftPattern)',
      'pattern.render() SVG (via draftPattern)',
    ],
  }
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n')
  rmSync(tmp, { recursive: true, force: true })
  console.log(`${design}: ${pageCount} pages, ${pieces.length} pieces, paper ${result.paper}`)
  return manifest
}

const body = testBodyCentimetres()
mkdirSync(outRoot, { recursive: true })
mkdirSync(artifactRoot, { recursive: true })
const manifests = []
for (const design of DESIGNS_TO_EXPORT) {
  manifests.push(await exportDesign(design, body))
}
writeFileSync(join(outRoot, 'manifest.json'), JSON.stringify({ designs: manifests }, null, 2) + '\n')
run('cp', ['-R', outRoot + '/.', artifactRoot + '/'])
console.log('wrote', outRoot)
console.log('wrote', artifactRoot)
