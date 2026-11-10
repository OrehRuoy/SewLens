import { isDegreeMeasurement, measurements as measurementCatalog } from '@freesewing/config'
import { plugin as pluginI18n } from '@freesewing/plugin-i18n'
import { plugin as pluginTransform } from '@freesewing/plugin-transform'
import { clampOptions, optionKinds } from './clamp.mjs'
import { DESIGN_NAMES, DESIGNS } from './designs.mjs'
import { patternPieces } from './geometry.mjs'
import { formatMeasurement, pieceLabel, translate, translatePhrase, uiLabels } from './labels.mjs'
import { renderPatternPdf } from './pdf.mjs'
import { normalizeLocale, normalizePaper, normalizeUnits, toMillimetres } from './units.mjs'
import { estimateYardage } from './yardage.mjs'

export class PatternInputError extends Error {
  constructor(message) {
    super(message)
    this.name = 'PatternInputError'
  }
}

function measurementMap(input, units) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new PatternInputError('measurements must be an object')
  }
  const output = {}
  for (const key of Object.keys(input).sort()) {
    if (!measurementCatalog.includes(key)) {
      throw new PatternInputError(`unknown measurement ${key}`)
    }
    const millimetres = toMillimetres(input[key], units, isDegreeMeasurement(key))
    if (millimetres == null) throw new PatternInputError(`measurement ${key} must be a number`)
    output[key] = millimetres
  }
  if (!Object.keys(output).length) throw new PatternInputError('measurements are required')
  return output
}

function seamAllowanceMm(input, units) {
  if (input == null || input === '') return 10
  const millimetres = toMillimetres(input, units)
  if (millimetres == null || millimetres < 0 || millimetres > 40) {
    throw new PatternInputError('seamAllowance must be between 0 and 4 cm (1.5 in)')
  }
  return millimetres
}

/**
 * Draft a FreeSewing design.
 * Measurements are centimetres when units are metric, and inches when imperial.
 * Shoulder slope stays in degrees. Percentage options are fractions (0.08) or
 * percent points inside the design's published range (8).
 */
export async function draftPattern(input = {}, runtime = {}) {
  const designName = String(input.design || '').trim().toLowerCase()
  const Design = DESIGNS[designName]
  if (!Design) {
    throw new PatternInputError(`design must be one of: ${DESIGN_NAMES.join(', ')}`)
  }
  const locale = normalizeLocale(input.locale || 'en')
  let units
  let paper
  try {
    units = normalizeUnits(input.units, input.locale || locale)
    paper = normalizePaper(input.paper, input.locale || locale, units)
  } catch (error) {
    throw new PatternInputError(error.message)
  }

  const measurementsMm = measurementMap(input.measurements, units)
  const kinds = optionKinds(Design)
  const prepared = {}
  for (const key of Object.keys(input.options || {}).sort()) {
    const value = input.options[key]
    prepared[key] = kinds[key] === 'mm' ? toMillimetres(value, units) : value
  }
  const options = clampOptions(Design, prepared)
  const saMm = seamAllowanceMm(input.seamAllowance, units)

  const pattern = new Design({
    measurements: measurementsMm,
    options,
    sa: saMm,
    units: units === 'imperial' ? 'imperial' : 'metric',
    locale,
    complete: true,
    paperless: false,
    layout: true,
    scale: 1,
  })
  pattern.use(pluginTransform)
  pattern.use(pluginI18n, (text) => translatePhrase(locale, text))
  try {
    pattern.draft()
  } catch (error) {
    throw new PatternInputError(error.message || 'pattern failed to draft')
  }
  const svg = pattern.render()
  const pieces = patternPieces(svg)
  const yardageMm = estimateYardage(pieces)
  const labels = uiLabels(locale)
  const legend = Object.keys(measurementsMm).map((key) =>
    formatMeasurement(locale, key, measurementsMm[key], units, isDegreeMeasurement(key))
  )

  let pdfBase64 = null
  if (runtime.pdf !== false) {
    const bytes = await renderPatternPdf({
      paper,
      locale,
      pieces,
      yardage: yardageMm,
      legend,
      seamAllowanceMm: saMm,
      units,
    })
    pdfBase64 = Buffer.from(bytes).toString('base64')
  }

  return {
    design: designName,
    locale,
    units,
    paper,
    seamAllowanceMm: saMm,
    appliedOptions: pattern.settings[0].options,
    measurementsMm,
    svg,
    pdfBase64,
    labels: {
      ...labels,
      design: translate(locale, `designs.${designName}`),
      pieces: pieces.map((piece) => ({ id: piece.name, label: pieceLabel(locale, piece.name) })),
    },
    yardage: yardageMm.map((row) => ({
      fabricCm: row.fabricCm,
      fabricIn: row.fabricIn,
      lengthMm: row.lengthMm,
      lengthCm: Math.round((row.lengthMm / 10) * 10) / 10,
      lengthIn: Math.round((row.lengthMm / 25.4) * 1000) / 1000,
    })),
    pages: {
      testSquareMm: 100,
      testSquareIn: 4,
    },
  }
}
