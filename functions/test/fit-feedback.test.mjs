import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DESIGNS, DESIGN_NAMES } from '../src/designs.mjs'
import { PatternInputError } from '../src/draft-pattern.mjs'
import {
  COMPLAINTS,
  applyComplaint,
  complaintsForDesign,
  memoryFeedbackStore,
  submitFitFeedback,
} from '../src/fit-feedback.mjs'
import { QuotaError, memoryQuotaStore } from '../src/quota.mjs'
import { runDraft } from '../src/run-draft.mjs'

const repo = join(dirname(fileURLToPath(import.meta.url)), '../..')
const INSTALL = 'install-fit-feedback'

const measurements = {
  chest: 96,
  waist: 82,
  hips: 98,
  neck: 38,
  shoulderSlope: 13,
  hpsToWaistBack: 45,
}

function rangeOf(design, option) {
  const rule = DESIGNS[design].patternConfig.options[option]
  return { min: rule.min / 100, max: rule.max / 100 }
}

describe('fit feedback deltas stay inside the published ranges', () => {
  test('the client copy matches the function table', () => {
    const client = JSON.parse(readFileSync(join(repo, 'data/fit_feedback.json'), 'utf8'))
    expect(client.complaints).toEqual(COMPLAINTS)
  })

  test('every supported design has a complaint and every delta clamps', () => {
    for (const name of DESIGN_NAMES) {
      const Design = DESIGNS[name]
      const complaints = complaintsForDesign(Design)
      expect(complaints.length).toBeGreaterThan(0)
      for (const complaint of complaints) {
        const { min, max } = rangeOf(name, complaint.option)
        for (const start of [min, (min + max) / 2, max]) {
          const options = applyComplaint(Design, { [complaint.option]: start }, complaint.id)
          const value = options[complaint.option]
          expect(value).toBeGreaterThanOrEqual(min - 1e-9)
          expect(value).toBeLessThanOrEqual(max + 1e-9)
          const room = start + complaint.delta
          if (room > min + 1e-9 && room < max - 1e-9) expect(value).toBeCloseTo(room, 5)
        }
      }
    }
  })

  test('an unknown complaint or the wrong design is rejected', () => {
    expect(() => applyComplaint(DESIGNS.aaron, {}, 'not-a-complaint')).toThrow(PatternInputError)
    expect(() => applyComplaint(DESIGNS.aaron, {}, 'waist_tight')).toThrow(/does not apply/)
  })
})

describe('anonymous fit notes', () => {
  test('the stored note has no install id, measurements, or photo', async () => {
    const store = memoryFeedbackStore()
    const logs = []
    const result = await submitFitFeedback(
      {
        design: 'brian',
        complaint: 'chest_tight',
        options: { chestEase: 0.08 },
        locale: 'de',
        installId: INSTALL,
        measurements,
        photo: 'secret',
      },
      { store, log: (entry) => logs.push(entry) }
    )
    expect(result.complaint).toBe('chest_tight')
    expect(result.options.chestEase).toBeCloseTo(0.1, 5)
    expect(logs[0]).toMatchObject({ event: 'fit_feedback', design: 'brian', complaint: 'chest_tight', locale: 'de' })
    const saved = store.snapshot()
    expect(saved).toHaveLength(1)
    expect(saved[0]).toEqual({
      design: 'brian',
      complaint: 'chest_tight',
      option: 'chestEase',
      delta: 0.02,
      locale: 'de',
      createdAt: expect.any(String),
    })
    expect(JSON.stringify(saved[0])).not.toMatch(/install|measurement|photo|secret/i)
  })
})

describe('a fit adjustment redrafts the same pattern', () => {
  test('the second design is refused and the same design is not charged again', async () => {
    const store = memoryQuotaStore()
    const input = {
      design: 'brian',
      measurements,
      units: 'metric',
      locale: 'en',
      paper: 'a4',
      installId: INSTALL,
    }
    await runDraft(input, { appCheck: true, store, pdf: false })
    expect(store.snapshot()[INSTALL]).toBe(1)
    await expect(
      runDraft({ ...input, design: 'aaron' }, { appCheck: true, store, pdf: false })
    ).rejects.toThrow(QuotaError)
    const feedback = memoryFeedbackStore()
    const again = await runDraft(
      { ...input, fitAdjustment: true, complaint: 'chest_tight', options: { chestEase: 0.1 } },
      { appCheck: true, store, feedback, pdf: false }
    )
    expect(again.design).toBe('brian')
    expect(again.options.chestEase).toBeCloseTo(0.12, 5)
    expect(feedback.snapshot()[0].complaint).toBe('chest_tight')
    expect(feedback.snapshot()[0].installId).toBeUndefined()
    expect(store.snapshot()[INSTALL]).toBe(1)
    await expect(
      runDraft({ ...input, design: 'aaron', fitAdjustment: true }, { appCheck: true, store, pdf: false })
    ).rejects.toThrow(QuotaError)
    expect(store.snapshot()[INSTALL]).toBe(1)
  })

  test('adjusting before the first draft is refused', async () => {
    const store = memoryQuotaStore()
    await expect(
      runDraft(
        {
          design: 'brian',
          measurements,
          units: 'metric',
          locale: 'en',
          paper: 'a4',
          installId: INSTALL,
          fitAdjustment: true,
        },
        { appCheck: true, store, pdf: false }
      )
    ).rejects.toThrow(QuotaError)
    expect(store.snapshot()[INSTALL]).toBeUndefined()
  })
})
