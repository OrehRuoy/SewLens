/** Locale, paper, and measurement units for draftPattern. */

export const LOCALES = ['en', 'de', 'fr', 'es', 'pt-BR', 'ja', 'it', 'nl']

const LETTER_REGIONS = new Set(['US', 'CA', 'MX', 'PH', 'CL', 'CO', 'VE'])

export const PAPER_MM = {
  letter: { width: 215.9, height: 279.4 },
  a4: { width: 210, height: 297 },
}

export function normalizeLocale(locale) {
  const raw = String(locale || 'en').trim().replace('_', '-')
  const lower = raw.toLowerCase()
  if (lower === 'pt-br' || lower === 'pt') return 'pt-BR'
  if (lower.startsWith('en')) return 'en'
  if (lower.startsWith('de')) return 'de'
  if (lower.startsWith('fr')) return 'fr'
  if (lower.startsWith('es')) return 'es'
  if (lower.startsWith('ja')) return 'ja'
  if (lower.startsWith('it')) return 'it'
  if (lower.startsWith('nl')) return 'nl'
  return 'en'
}

export function regionOf(locale) {
  const parts = String(locale || '').replace('_', '-').split('-')
  if (parts.length < 2) return ''
  return parts[1].toUpperCase()
}

export function normalizeUnits(units, locale) {
  if (units === 'imperial' || units === 'in' || units === 'inch' || units === 'inches') return 'imperial'
  if (units === 'metric' || units === 'cm' || units === 'mm') return 'metric'
  if (units) throw new Error(`units must be metric or imperial`)
  const region = regionOf(locale)
  if (region === 'US' || region === 'CA' || region === 'LR') return 'imperial'
  return 'metric'
}

export function normalizePaper(paper, locale, units) {
  const name = String(paper || '').toLowerCase()
  if (name === 'letter' || name === 'a4') return name
  if (paper) throw new Error(`paper must be letter or a4`)
  if (LETTER_REGIONS.has(regionOf(locale))) return 'letter'
  if (units === 'imperial' && String(locale || '').toLowerCase().startsWith('en')) return 'letter'
  return 'a4'
}

export function toMillimetres(value, units, degree = false) {
  const number = Number(value)
  if (!Number.isFinite(number)) return null
  if (degree) return number
  if (units === 'imperial') return number * 25.4
  return number * 10
}

export function fromMillimetres(mm, units) {
  if (units === 'imperial') return Math.round((mm / 25.4) * 1000) / 1000
  return Math.round((mm / 10) * 100) / 100
}

export const PT_PER_MM = 72 / 25.4
export const PT_PER_IN = 72
