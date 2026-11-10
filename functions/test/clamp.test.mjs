import { draftPattern, PatternInputError } from '../src/draft-pattern.mjs'
import { normalizePaper } from '../src/units.mjs'

const measurements = {
  chest: 96,
  waist: 82,
  hips: 98,
  neck: 38,
  shoulderSlope: 13,
  hpsToWaistBack: 45,
}

describe('draftPattern contract', () => {
  test('clamps percentage options into the design range', async () => {
    const result = await draftPattern(
      {
        design: 'brian',
        measurements,
        options: { chestEase: 80 },
        units: 'metric',
        locale: 'en',
        paper: 'a4',
      },
      { pdf: false }
    )
    expect(result.appliedOptions.chestEase).toBeCloseTo(0.35, 5)
  })

  test('the same input drafts the same SVG', async () => {
    const input = { design: 'brian', measurements, units: 'metric', locale: 'de', paper: 'a4' }
    const first = await draftPattern(input, { pdf: false })
    const second = await draftPattern(input, { pdf: false })
    expect(second.svg).toBe(first.svg)
  })

  test('paper follows the locale when it is omitted', () => {
    expect(normalizePaper(undefined, 'en-US', 'imperial')).toBe('letter')
    expect(normalizePaper(undefined, 'es-MX', 'metric')).toBe('letter')
    expect(normalizePaper(undefined, 'de', 'metric')).toBe('a4')
    expect(normalizePaper(undefined, 'ja', 'metric')).toBe('a4')
    expect(normalizePaper('a4', 'en-US', 'imperial')).toBe('a4')
  })

  test('unknown designs are rejected', async () => {
    await expect(
      draftPattern({ design: 'not-a-design', measurements, units: 'metric' }, { pdf: false })
    ).rejects.toBeInstanceOf(PatternInputError)
  })
})
