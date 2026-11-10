/** Store product ids from docs/ids.md. */

export const CREDIT_PRODUCT = 'orehruoy.sewlens.credit'
export const UNLIMITED_PRODUCT = 'orehruoy.sewlens.unlimited'
export const BUNDLE_ID = 'com.sewlens.app'

export function productKind(productId) {
  if (productId === CREDIT_PRODUCT) return 'credit'
  if (productId === UNLIMITED_PRODUCT) return 'unlimited'
  return ''
}
