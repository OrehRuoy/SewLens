import { pickDesign } from './pick-design.mjs'
import { memoryQuotaStore } from './quota.mjs'

/** Score a labeled photo set. The job passes at 16 or more correct designs out of 20. */
export async function scoreCases(cases, client, runtime = {}) {
  const store = runtime.store || memoryQuotaStore()
  const details = []
  let correct = 0
  for (const item of cases) {
    try {
      const result = await pickDesign(
        {
          photo: item.photo,
          locale: item.locale || 'en',
          installId: item.installId || 'regression-install',
        },
        { appCheck: true, store, client, log: runtime.log }
      )
      const ok = result.design === item.design && !result.unsupported
      if (ok) correct += 1
      details.push({ id: item.id, expected: item.design, actual: result.design, ok })
    } catch (error) {
      details.push({ id: item.id, expected: item.design, actual: null, ok: false, error: error.name })
    }
  }
  const total = cases.length
  return { correct, total, passed: total >= 20 && correct >= 16, details }
}
