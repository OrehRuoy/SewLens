import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { designs as freesewingDesigns, measurements as freesewingMeasurements } from '@freesewing/i18n'
import { fromMillimetres, LOCALES, normalizeLocale } from './units.mjs'

const directory = join(dirname(fileURLToPath(import.meta.url)), '../i18n')

export const catalogs = Object.fromEntries(
  LOCALES.map((locale) => [locale, JSON.parse(readFileSync(join(directory, `${locale}.json`), 'utf8'))])
)

const PART_TOKENS = [
  'interfacing',
  'undersleeve',
  'topsleeve',
  'waistband',
  'binding',
  'facing',
  'lining',
  'sleeve',
  'collar',
  'pocket',
  'front',
  'back',
  'hood',
  'yoke',
  'brim',
  'skirt',
  'gusset',
  'cuff',
  'side',
  'band',
  'top',
  'hem',
  'neck',
  'loop',
  'tail',
  'tip',
]

export function translate(locale, key) {
  const language = catalogs[locale] ? locale : normalizeLocale(locale)
  if (language === 'en' && key.startsWith('measurements.')) {
    const name = key.slice('measurements.'.length)
    if (freesewingMeasurements[name]) return freesewingMeasurements[name]
  }
  if (language === 'en' && key.startsWith('designs.')) {
    const name = key.slice('designs.'.length)
    if (freesewingDesigns[name]?.t) return freesewingDesigns[name].t
  }
  const [group, leaf] = key.split('.')
  const value = catalogs[language]?.[group]?.[leaf]
  if (typeof value === 'string' && value.length) return value
  return `{{missing:${key}}}`
}

export function pieceLabel(locale, partName) {
  const tail = String(partName).split('.').pop() || String(partName)
  const lower = tail.toLowerCase()
  for (const token of PART_TOKENS) {
    if (lower.includes(token)) return translate(locale, `parts.${token}`)
  }
  return tail
}

export function uiLabels(locale) {
  const labels = {}
  for (const key of Object.keys(catalogs.en.ui)) labels[key] = translate(locale, `ui.${key}`)
  return labels
}

export function measurementLabel(locale, name) {
  return translate(locale, `measurements.${name}`)
}

export function formatMeasurement(locale, name, mm, units, degree = false) {
  const label = measurementLabel(locale, name)
  if (degree) return `${label}: ${Math.round(mm * 10) / 10}°`
  const value = fromMillimetres(mm, units)
  const unit = units === 'imperial' ? 'in' : 'cm'
  return `${label}: ${value} ${unit}`
}

/** Translate FreeSewing's English part titles when they match our glossary. */
export function translatePhrase(locale, text) {
  if (typeof text !== 'string') return text
  for (const token of PART_TOKENS) {
    if (text === catalogs.en.parts[token]) return translate(locale, `parts.${token}`)
  }
  return text
}
