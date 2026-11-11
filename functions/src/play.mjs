import { BUNDLE_ID } from './products.mjs'
import { ReceiptError } from './receipts.mjs'

const SCOPE = 'https://www.googleapis.com/auth/androidpublisher'
const TOKEN_URL = `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?scopes=${encodeURIComponent(SCOPE)}`

/**
 * Play Developer API purchases.products.get.
 * Cloud Functions uses the runtime service account. That account must be
 * invited in Play Console with access to this app's orders.
 */
export function playPurchases({ fetchImpl = fetch, packageName = BUNDLE_ID, tokenUrl = TOKEN_URL } = {}) {
  return {
    async get(productId, token) {
      const access = await accessToken(fetchImpl, tokenUrl)
      const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`
      const response = await fetchImpl(url, { headers: { Authorization: `Bearer ${access}` } })
      if (!response.ok) throw new ReceiptError('purchase is not valid')
      const body = await response.json()
      if (!body || body.purchaseState !== 0 || !body.orderId) throw new ReceiptError('purchase is not valid')
      return { purchaseState: 0, orderId: String(body.orderId), revoked: false }
    },
  }
}

async function accessToken(fetchImpl, tokenUrl) {
  let response
  try {
    response = await fetchImpl(tokenUrl, { headers: { 'Metadata-Flavor': 'Google' } })
  } catch {
    throw new ReceiptError('Play verification is not configured')
  }
  if (!response.ok) throw new ReceiptError('Play verification is not configured')
  const body = await response.json()
  const token = String(body.access_token || '')
  if (!token) throw new ReceiptError('Play verification is not configured')
  return token
}
