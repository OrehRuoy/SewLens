/** Clamp caller options to the ranges published by each FreeSewing design. */

function clamp(value, min, max) {
  let next = value
  if (Number.isFinite(min)) next = Math.max(min, next)
  if (Number.isFinite(max)) next = Math.min(max, next)
  return next
}

function optionKind(rule) {
  if (!rule || typeof rule !== 'object') return 'raw'
  if (Object.prototype.hasOwnProperty.call(rule, 'bool')) return 'bool'
  if (Object.prototype.hasOwnProperty.call(rule, 'pct')) return 'pct'
  if (Object.prototype.hasOwnProperty.call(rule, 'mm')) return 'mm'
  if (Object.prototype.hasOwnProperty.call(rule, 'deg')) return 'deg'
  if (Object.prototype.hasOwnProperty.call(rule, 'count')) return 'count'
  if (Array.isArray(rule.list)) return 'list'
  return 'raw'
}

/**
 * Percentage options are fractions in FreeSewing (0.08 = 8%).
 * A value inside the published percent range (for example 8 with max 20)
 * is read as percent points and converted to a fraction.
 */
export function clampOptions(Design, input = {}) {
  const spec = Design.patternConfig?.options || {}
  const output = {}
  for (const key of Object.keys(input).sort()) {
    if (!Object.prototype.hasOwnProperty.call(spec, key)) continue
    const rule = spec[key]
    const kind = optionKind(rule)
    const raw = input[key]
    if (kind === 'bool') {
      output[key] = Boolean(raw)
      continue
    }
    if (kind === 'list') {
      output[key] = rule.list.includes(raw) ? raw : rule.list[0]
      continue
    }
    if (kind === 'raw') {
      output[key] = raw
      continue
    }
    const numeric = Number(raw)
    if (!Number.isFinite(numeric)) continue
    if (kind === 'pct') {
      const min = (rule.min ?? 0) / 100
      const max = (rule.max ?? 0) / 100
      let fraction = numeric
      if (fraction > max && fraction >= (rule.min ?? 0) && fraction <= (rule.max ?? 0)) {
        fraction = fraction / 100
      }
      output[key] = clamp(fraction, min, max)
      continue
    }
    if (kind === 'count') {
      output[key] = clamp(Math.round(numeric), rule.min ?? 0, rule.max ?? Number.POSITIVE_INFINITY)
      continue
    }
    output[key] = clamp(numeric, rule.min ?? Number.NEGATIVE_INFINITY, rule.max ?? Number.POSITIVE_INFINITY)
  }
  return output
}

export function optionKinds(Design) {
  const spec = Design.patternConfig?.options || {}
  const kinds = {}
  for (const [key, rule] of Object.entries(spec)) kinds[key] = optionKind(rule)
  return kinds
}
