/** Gemini Flash, with Flash-Lite as the fallback model. */

export const FLASH_MODEL = process.env.GEMINI_FLASH_MODEL || 'gemini-3.8-flash'
export const FLASH_LITE_MODEL = process.env.GEMINI_FLASH_LITE_MODEL || 'gemini-3.5-flash-lite'

export function createGeminiClient({ apiKey, fetchImpl = fetch } = {}) {
  return {
    async generate({ model, prompt, schema, photo }) {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`
      let response
      try {
        response = await fetchImpl(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{
              role: 'user',
              parts: [
                { text: prompt },
                { inline_data: { mime_type: photo.mimeType, data: photo.data } },
              ],
            }],
            generationConfig: {
              temperature: 0,
              responseMimeType: 'application/json',
              responseSchema: schema,
            },
          }),
        })
      } catch (error) {
        throw new Error(`Gemini ${model} request failed`)
      }
      if (!response.ok) {
        let detail = ''
        try {
          const body = await response.json()
          detail = String(body?.error?.message || '').replace(/key=[^&\s]+/gi, 'key=redacted').slice(0, 240)
        } catch {
          detail = ''
        }
        throw new Error(`Gemini ${model} failed with status ${response.status}${detail ? `: ${detail}` : ''}`)
      }
      const payload = await response.json()
      const text = payload?.candidates?.[0]?.content?.parts?.map((part) => part.text || '').join('') || ''
      const usage = payload?.usageMetadata || {}
      return {
        text,
        tokens: {
          prompt: Number(usage.promptTokenCount) || 0,
          output: Number(usage.candidatesTokenCount) || 0,
          total: Number(usage.totalTokenCount) || 0,
        },
      }
    },
  }
}
