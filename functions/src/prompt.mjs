import { DESIGN_NAMES } from './designs.mjs'
import { LANGUAGE_NAMES } from './language.mjs'

/** What each design looks like in a photo. The model returns the id, never the display name. */
export const DESIGN_GUIDE = [
  ['aaron', 'sleeveless knit tank top or A-shirt, bound neck and armholes, no collar and no buttons'],
  ['bella', 'fitted bodice block or muslin with a bust dart, a torso sloper rather than a finished fashion top'],
  ['bent', 'body block or muslin with a two-piece sleeve, a tailored torso sloper'],
  ['brian', 'plain body block or muslin with a one-piece sleeve, no collar and no hood'],
  ['bruce', 'boxer briefs: underwear with a short leg, not outerwear shorts'],
  ['charlie', 'chinos: casual trousers with slant pockets, belt loops, a fly, and a structured waistband'],
  ['florent', 'flat cap or newsboy cap with a soft brim in front'],
  ['hugo', 'hoodie: a hood, long sleeves, and a sweatshirt body, often with a kangaroo pocket'],
  ['jaeger', 'tailored jacket or sport coat with a lapel, not a hoodie and not a vest'],
  ['lily', 'leggings: tight stretch pants from waist to ankle, no fly'],
  ['paco', 'casual trousers or sweatpants with a relaxed fit, not chinos and not a plain dress-trouser block'],
  ['penelope', 'pencil skirt: a straight fitted skirt to around the knee, no flare'],
  ['sandy', 'circle skirt: a full skirt with a lot of flare'],
  ['simon', 'classic button-up shirt with a collar, cuffs, and a yoke, menswear fit, no bust dart'],
  ['simone', 'button-up shirt with a collar, fitted through the bust, a womenswear shirt'],
  ['teagan', 'T-shirt: a knit top with sleeves and a crew or scoop neck, no buttons and no hood'],
  ['titan', 'plain trouser block or dress-trouser sloper, simple legs, no cargo pockets'],
  ['trayvon', 'a necktie'],
  ['umbra', 'briefs or bikini underwear with no leg, not boxer briefs'],
  ['wahid', 'waistcoat or vest worn over a shirt, sleeveless, with a front opening, not a tank top'],
]

export function responseSchema() {
  return {
    type: 'object',
    propertyOrdering: ['design', 'unsupported', 'confidence', 'options', 'explanation'],
    required: ['design', 'unsupported', 'confidence', 'options', 'explanation'],
    properties: {
      design: { type: 'string', enum: [...DESIGN_NAMES, 'unsupported'] },
      unsupported: { type: 'string', enum: ['none', 'shorts', 'polo'] },
      confidence: { type: 'number' },
      options: {
        type: 'array',
        items: {
          type: 'object',
          required: ['key', 'value'],
          properties: {
            key: { type: 'string' },
            value: { type: 'string' },
          },
        },
      },
      explanation: { type: 'string' },
    },
  }
}

export function buildPickPrompt(locale) {
  const language = LANGUAGE_NAMES[locale] || 'English'
  const lines = DESIGN_GUIDE.map(([id, description]) => `- ${id}: ${description}`)
  return [
    'You match one garment photo to a sewing-pattern design.',
    'Choose the single closest design id from this list:',
    ...lines,
    'If the garment is outerwear shorts, set unsupported to "shorts" and design to "unsupported". Boxer briefs are bruce, not shorts.',
    'If the garment is a polo shirt (a knit shirt with a collar and a short button placket), set unsupported to "polo" and design to "unsupported". A button-up shirt is simon or simone. A plain T-shirt is teagan.',
    'Otherwise set unsupported to "none" and design to exactly one id from the list.',
    'confidence is a number from 0 to 1. Use a value below 0.6 when the photo is unclear or more than one design could match.',
    'options is an array of {key, value} using option keys for that design only. Leave options empty when you are unsure. Ease values are percent points, so 15 means 15 percent.',
    `Write the explanation in ${language}. One or two short sentences about the garment in the photo. Do not invent a design title.`,
  ].join('\n')
}
