import { measurements as freesewingMeasurements } from '@freesewing/i18n'
import { draftPattern } from '../src/draft-pattern.mjs'
import { measurementLabel, translate, uiLabels } from '../src/labels.mjs'
import { LOCALES } from '../src/units.mjs'

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
  inseam: 78,
  waistToFloor: 108,
}

describe('localized labels', () => {
  test('English measurement names come from @freesewing/i18n', () => {
    expect(measurementLabel('en', 'chest')).toBe(freesewingMeasurements.chest)
    expect(measurementLabel('en', 'inseam')).toBe(freesewingMeasurements.inseam)
  })

  test('all eight locales have the UI strings and no missing-key markers', () => {
    const bundle = {}
    for (const locale of LOCALES) {
      bundle[locale] = uiLabels(locale)
      for (const [key, value] of Object.entries(bundle[locale])) {
        expect(value).not.toContain('{{missing:')
        expect(value.length).toBeGreaterThan(0)
        expect(key).toBeTruthy()
      }
    }
    expect(bundle).toMatchSnapshot()
  })

  test('a missing key is marked', () => {
    expect(translate('de', 'ui.notARealKey')).toBe('{{missing:ui.notARealKey}}')
  })

  test('a drafted pattern legend has no missing-key markers', async () => {
    for (const locale of LOCALES) {
      const result = await draftPattern(
        { design: 'brian', measurements, units: 'metric', locale, paper: 'a4' },
        { pdf: false }
      )
      const packed = JSON.stringify(result.labels)
      expect(packed).not.toContain('{{missing:')
      expect(packed).toContain(uiLabels(locale).legend)
      expect(packed).toContain(uiLabels(locale).assembly)
    }
  })
})
