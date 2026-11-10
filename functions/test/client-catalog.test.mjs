import { readFileSync } from 'node:fs'
import { DESIGNS, DESIGN_NAMES } from '../src/designs.mjs'
import {
  CATALOG_PATH,
  STRINGS_PATH,
  buildCatalog,
  catalogJson,
  mergeStrings,
  parseCsv,
} from '../scripts/client-catalog.mjs'

describe('client design catalog', () => {
  test('data/designs.json matches the FreeSewing designs', () => {
    expect(readFileSync(CATALOG_PATH, 'utf8')).toBe(catalogJson())
  })

  test('strings.csv carries the generated design and measurement names', () => {
    const text = readFileSync(STRINGS_PATH, 'utf8')
    expect(mergeStrings(text)).toBe(text)
  })

  test('every design lists its required measurements and valid sliders', () => {
    const catalog = buildCatalog()
    expect(Object.keys(catalog.designs)).toEqual(DESIGN_NAMES)
    for (const name of DESIGN_NAMES) {
      const entry = catalog.designs[name]
      expect(entry.measurements).toEqual([...DESIGNS[name].patternConfig.measurements].sort())
      for (const key of entry.measurements) expect(catalog.measurements[key]).toBeDefined()
      for (const slider of entry.sliders) {
        expect(slider.min).toBeLessThanOrEqual(slider.default)
        expect(slider.default).toBeLessThanOrEqual(slider.max)
      }
    }
  })

  test('typical values sit inside the accepted range', () => {
    for (const [key, spec] of Object.entries(buildCatalog().measurements)) {
      expect([key, spec.min <= spec.typical && spec.typical <= spec.max]).toEqual([key, true])
    }
  })

  test('every slider and measurement has a string row in all 8 locales', () => {
    const rows = parseCsv(readFileSync(STRINGS_PATH, 'utf8'))
    const keys = new Map(rows.slice(1).map((row) => [row[0], row.slice(1)]))
    const catalog = buildCatalog()
    const needed = [
      ...Object.keys(catalog.measurements).flatMap((key) => [`meas_${key}`, `how_${key}`]),
      ...new Set(Object.values(catalog.designs).flatMap((d) => d.sliders.map((s) => `opt_${s.key}`))),
      ...catalog.categories.map((group) => `cat_${group}`),
    ]
    for (const key of needed) {
      expect([key, keys.has(key)]).toEqual([key, true])
      expect([key, keys.get(key).filter((cell) => cell.trim() !== '').length]).toEqual([key, 8])
    }
  })
})
