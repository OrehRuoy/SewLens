import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { clampOptions } from './clamp.mjs'
import { DESIGN_NAMES, DESIGNS } from './designs.mjs'
import { PatternInputError } from './draft-pattern.mjs'
import { normalizeLocale } from './units.mjs'

/**
 * Fit complaints and the option change each one makes.
 * Deltas are fractions (0.02 = 2 percentage points). A tight complaint adds
 * ease. A tight stretch complaint lowers the stretch, which cuts the pattern larger.
 * The copy in data/fit_feedback.json is what the Godot client shows.
 */
const RULE_PATH = join(dirname(fileURLToPath(import.meta.url)), 'fit-feedback.json')
export const FIT_RULES = JSON.parse(readFileSync(RULE_PATH, 'utf8'))
export const COMPLAINTS = FIT_RULES.complaints

const STORED_FIELDS = ['design', 'complaint', 'option', 'delta', 'locale', 'createdAt']

function asFraction(rule, value) {
  const max = (rule.max ?? 0) / 100
  const numeric = Number(value)
  if (!Number.isFinite(numeric)) return (rule.pct ?? 0) / 100
  if (numeric > max && numeric >= (rule.min ?? 0) && numeric <= (rule.max ?? 0)) return numeric / 100
  return numeric
}

export function complaintById(id) {
  return COMPLAINTS.find((item) => item.id === id) || null
}

/** Complaints whose option this design actually publishes. */
export function complaintsForDesign(Design) {
  const spec = Design?.patternConfig?.options || {}
  return COMPLAINTS.filter((item) => {
    const rule = spec[item.option]
    return rule && typeof rule === 'object' && rule.pct !== undefined
  })
}

/**
 * Add one complaint's delta and clamp to the design's published range.
 * Unknown complaints and options the design does not have are rejected.
 */
export function applyComplaint(Design, options, complaintId) {
  const complaint = complaintById(complaintId)
  if (!complaint) throw new PatternInputError('unknown fit complaint')
  const rule = Design?.patternConfig?.options?.[complaint.option]
  if (!rule || rule.pct === undefined) throw new PatternInputError('complaint does not apply to this design')
  const fraction = asFraction(rule, options?.[complaint.option])
  const next = { ...(options || {}), [complaint.option]: fraction + complaint.delta }
  return clampOptions(Design, next)
}

/** Anonymous fit note. installId, measurements, and photos are never stored. */
export function memoryFeedbackStore() {
  const docs = []
  return {
    async save(doc) {
      const stored = {}
      for (const key of STORED_FIELDS) stored[key] = doc[key]
      docs.push(stored)
    },
    snapshot() {
      return docs.map((doc) => ({ ...doc }))
    },
  }
}

/**
 * submitFitFeedback(design, complaint, options, locale)
 * Stores an anonymous note and returns the clamped options. It does not draft.
 */
export async function submitFitFeedback(input = {}, runtime = {}) {
  if (runtime.appCheck === false) throw new PatternInputError('App Check is required')
  const designName = String(input.design || '').trim().toLowerCase()
  const Design = DESIGNS[designName]
  if (!Design) throw new PatternInputError(`design must be one of: ${DESIGN_NAMES.join(', ')}`)
  const complaintId = String(input.complaint || '').trim()
  const options = applyComplaint(Design, input.options || {}, complaintId)
  const complaint = complaintById(complaintId)
  if (!runtime.store) throw new PatternInputError('feedback store is required')
  const locale = normalizeLocale(input.locale || 'en')
  await runtime.store.save({
    design: designName,
    complaint: complaint.id,
    option: complaint.option,
    delta: complaint.delta,
    locale,
    createdAt: new Date().toISOString(),
  })
  runtime.log?.({ event: 'fit_feedback', design: designName, complaint: complaint.id, locale })
  return { design: designName, complaint: complaint.id, options }
}
