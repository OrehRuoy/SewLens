/**
 * Builds the Godot client's design catalog and the generated name rows of
 * i18n/strings.csv from the same FreeSewing designs and label bundles the
 * functions use.
 *
 *   node scripts/client-catalog.mjs          write data/designs.json + strings.csv rows
 *   node scripts/client-catalog.mjs --check  exit 1 when either file is stale
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { isDegreeMeasurement } from '@freesewing/config'
import { DESIGNS, DESIGN_NAMES } from '../src/designs.mjs'
import { translate } from '../src/labels.mjs'
import { LOCALES } from '../src/units.mjs'

const repo = join(dirname(fileURLToPath(import.meta.url)), '../..')
export const CATALOG_PATH = join(repo, 'data/designs.json')
export const STRINGS_PATH = join(repo, 'i18n/strings.csv')

export const CATEGORIES = {
  tops: ['aaron', 'hugo', 'jaeger', 'simon', 'simone', 'teagan', 'wahid'],
  bottoms: ['bruce', 'charlie', 'lily', 'paco', 'penelope', 'sandy', 'umbra'],
  accessories: ['florent', 'trayvon'],
  blocks: ['bella', 'bent', 'brian', 'titan'],
}

/** Options shown as sliders, in display order. Each has an opt_<key> string row. */
export const SLIDER_OPTIONS = [
  'chestEase',
  'waistEase',
  'hipsEase',
  'seatEase',
  'bicepsEase',
  'kneeEase',
  'headEase',
  'lengthBonus',
  'sleeveLengthBonus',
  'legBonus',
  'stretch',
  'fabricStretch',
  'xStretch',
]
export const MAX_SLIDERS = 4

/**
 * Accepted range and a typical adult value, in millimetres (degrees for
 * shoulderSlope). Values outside the range are rejected as typos.
 */
export const MEASUREMENT_RANGES = {
  ankle: [150, 400, 240],
  biceps: [150, 600, 310],
  bustFront: [250, 900, 500],
  bustPointToUnderbust: [30, 200, 90],
  bustSpan: [100, 300, 190],
  chest: [550, 1700, 1000],
  crossSeam: [450, 1200, 760],
  crossSeamFront: [200, 600, 360],
  head: [420, 680, 570],
  heel: [220, 420, 320],
  highBust: [600, 1600, 920],
  highBustFront: [280, 850, 470],
  hips: [550, 1700, 950],
  hpsToBust: [140, 420, 260],
  hpsToWaistBack: [280, 620, 440],
  hpsToWaistFront: [300, 680, 460],
  knee: [220, 600, 380],
  neck: [250, 560, 370],
  seat: [650, 1800, 1000],
  seatBack: [320, 950, 500],
  shoulderSlope: [3, 30, 13],
  shoulderToElbow: [220, 480, 350],
  shoulderToShoulder: [280, 580, 430],
  shoulderToWrist: [420, 800, 600],
  underbust: [500, 1500, 780],
  upperLeg: [350, 950, 580],
  waist: [450, 1600, 800],
  waistBack: [220, 800, 400],
  waistToArmpit: [130, 380, 230],
  waistToFloor: [750, 1300, 1050],
  waistToHips: [20, 220, 110],
  waistToKnee: [420, 720, 580],
  waistToSeat: [100, 320, 200],
  waistToUnderbust: [30, 220, 100],
  waistToUpperLeg: [180, 420, 280],
  wrist: [110, 260, 170],
}

function round(value) {
  return Math.round(value * 1000) / 1000
}

export function buildCatalog() {
  const designs = {}
  const used = new Set()
  for (const name of DESIGN_NAMES) {
    const config = DESIGNS[name].patternConfig || {}
    const measurements = [...(config.measurements || [])].sort()
    for (const key of measurements) used.add(key)
    const options = config.options || {}
    const sliders = []
    for (const key of SLIDER_OPTIONS) {
      const rule = options[key]
      if (!rule || typeof rule !== 'object' || rule.pct === undefined) continue
      if (sliders.length >= MAX_SLIDERS) break
      sliders.push({ key, min: round(rule.min), max: round(rule.max), default: round(rule.pct) })
    }
    const category = Object.keys(CATEGORIES).find((group) => CATEGORIES[group].includes(name))
    if (!category) throw new Error(`design ${name} has no category`)
    designs[name] = { category, measurements, sliders }
  }
  const measurements = {}
  for (const key of [...used].sort()) {
    const range = MEASUREMENT_RANGES[key]
    if (!range) throw new Error(`measurement ${key} has no range`)
    measurements[key] = {
      kind: isDegreeMeasurement(key) ? 'degree' : 'length',
      min: range[0],
      max: range[1],
      typical: range[2],
    }
  }
  return { categories: Object.keys(CATEGORIES), designs, measurements }
}

export function catalogJson() {
  return JSON.stringify(buildCatalog(), null, 2) + '\n'
}

const CSV_COLUMNS = ['en', 'de', 'fr', 'es', 'pt_BR', 'ja', 'it', 'nl']
const LOCALE_FOR_COLUMN = Object.fromEntries(
  CSV_COLUMNS.map((column) => [column, LOCALES.find((code) => code.replace('-', '_') === column)])
)

/** Rows the generator owns: design_<name> and meas_<key>. */
export function generatedRows() {
  const catalog = buildCatalog()
  const rows = []
  for (const name of Object.keys(catalog.designs)) {
    rows.push([`design_${name}`, ...CSV_COLUMNS.map((c) => translate(LOCALE_FOR_COLUMN[c], `designs.${name}`))])
  }
  for (const key of Object.keys(catalog.measurements)) {
    rows.push([`meas_${key}`, ...CSV_COLUMNS.map((c) => translate(LOCALE_FOR_COLUMN[c], `measurements.${key}`))])
  }
  for (const row of rows) {
    const missing = row.find((cell) => cell.startsWith('{{missing:'))
    if (missing) throw new Error(`label bundle gap: ${missing}`)
  }
  return rows
}

export function parseCsv(text) {
  const rows = []
  let row = []
  let cell = ''
  let quoted = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        cell += '"'
        i++
      } else if (ch === '"') {
        quoted = false
      } else {
        cell += ch
      }
    } else if (ch === '"') {
      quoted = true
    } else if (ch === ',') {
      row.push(cell)
      cell = ''
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++
      row.push(cell)
      rows.push(row)
      row = []
      cell = ''
    } else {
      cell += ch
    }
  }
  if (cell !== '' || row.length) {
    row.push(cell)
    rows.push(row)
  }
  return rows
}

function csvCell(value) {
  return /[",\n\r]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value
}

export function mergeStrings(text) {
  const rows = parseCsv(text)
  const header = rows[0]
  const generated = generatedRows()
  const owned = new Set(generated.map((row) => row[0]))
  const kept = rows.slice(1).filter((row) => row.length > 1 && !owned.has(row[0]))
  const body = [...kept, ...generated]
  return [header, ...body].map((row) => row.map(csvCell).join(',')).join('\n') + '\n'
}

function main(argv) {
  const check = argv.includes('--check')
  const json = catalogJson()
  const strings = mergeStrings(readFileSync(STRINGS_PATH, 'utf8'))
  let stale = false
  let currentJson = ''
  try {
    currentJson = readFileSync(CATALOG_PATH, 'utf8')
  } catch {
    currentJson = ''
  }
  if (currentJson !== json) {
    stale = true
    if (!check) writeFileSync(CATALOG_PATH, json)
  }
  if (readFileSync(STRINGS_PATH, 'utf8') !== strings) {
    stale = true
    if (!check) writeFileSync(STRINGS_PATH, strings)
  }
  if (check && stale) {
    console.error('data/designs.json or i18n/strings.csv is stale. Run: node functions/scripts/client-catalog.mjs')
    return 1
  }
  console.log(stale ? 'Wrote data/designs.json and strings.csv rows' : 'Client catalog is current')
  return 0
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2))
}
