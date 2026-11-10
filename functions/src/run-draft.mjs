import { draftPattern, PatternInputError } from './draft-pattern.mjs'
import { applyComplaint, complaintById } from './fit-feedback.mjs'
import { DESIGNS } from './designs.mjs'
import { assertInstallId, QuotaError } from './quota.mjs'
import { translate } from './labels.mjs'
import { normalizeLocale } from './units.mjs'

/**
 * Draft one pattern and consume the install's free pattern.
 * A failed draft releases the credit. The photo is not part of this call.
 */
export async function runDraft(input, runtime = {}) {
  if (!runtime.appCheck) throw new PatternInputError('App Check is required')
  const installId = assertInstallId(input?.installId, PatternInputError)
  const store = runtime.store
  if (!store) throw new PatternInputError('quota store is required')
  const designName = String(input?.design || '').trim().toLowerCase()
  const adjusting = input?.fitAdjustment === true
  try {
    if (adjusting) await store.assertAdjustment(installId, designName)
    else await store.reserve(installId, designName)
  } catch (error) {
    if (error instanceof QuotaError) {
      throw new QuotaError(translate(normalizeLocale(input?.locale), 'ui.rateLimited'))
    }
    throw error
  }
  let draftInput = input
  let fitOptions = null
  if (adjusting) {
    const Design = DESIGNS[designName]
    if (!Design) throw new PatternInputError(`unknown design ${designName}`)
    const complaintId = String(input?.complaint || '').trim()
    fitOptions = applyComplaint(Design, input?.options || {}, complaintId)
    draftInput = { ...input, options: fitOptions }
  }
  const started = Date.now()
  try {
    const result = await draftPattern(draftInput, runtime)
    const latency_ms = Date.now() - started
    if (fitOptions && runtime.feedback) {
      const complaint = complaintById(String(input.complaint).trim())
      const locale = result.locale
      await runtime.feedback.save({
        design: designName,
        complaint: complaint.id,
        option: complaint.option,
        delta: complaint.delta,
        locale,
        createdAt: new Date().toISOString(),
      })
      runtime.log?.({ event: 'fit_feedback', design: designName, complaint: complaint.id, locale })
    }
    runtime.log?.({
      event: 'pattern_drafted',
      latency_ms,
      design: result.design,
      locale: result.locale,
      fit_adjustment: adjusting,
    })
    return fitOptions ? { ...result, latency_ms, options: fitOptions } : { ...result, latency_ms }
  } catch (error) {
    if (!adjusting) await store.release(installId)
    throw error
  }
}
