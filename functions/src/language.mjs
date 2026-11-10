/** Detect the explanation language. German and Japanese are the checked locales. */

const GERMAN_WORDS = new Set([
  'der', 'die', 'das', 'und', 'nicht', 'ein', 'eine', 'einem', 'einen', 'einer',
  'ist', 'mit', 'für', 'auf', 'den', 'dem', 'des', 'dieses', 'dieser', 'nicht',
  'wähle', 'entwurf', 'noch', 'werden',
])

export const LANGUAGE_NAMES = {
  en: 'English',
  de: 'German',
  fr: 'French',
  es: 'Spanish',
  'pt-BR': 'Brazilian Portuguese',
  ja: 'Japanese',
  it: 'Italian',
  nl: 'Dutch',
}

export function detectLanguage(text) {
  const value = String(text || '')
  const japanese = (value.match(/[\u3040-\u30ff\u4e00-\u9fff]/g) || []).length
  if (japanese >= 4) return 'ja'
  const words = value.toLowerCase().match(/[a-zäöüß]+/g) || []
  const german = words.filter((word) => GERMAN_WORDS.has(word) || /[äöüß]/.test(word)).length
  if (german >= 2) return 'de'
  return 'und'
}
