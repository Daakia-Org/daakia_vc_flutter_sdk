const String languageJsonString = r'''
[
  {
    "code": "af-ZA",
    "language": "Afrikaans (South Africa)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/za.svg"
  },
  {
    "code": "ar-AE",
    "language": "Arabic",
    "support": ["Audio + human-labeled transcript", "Plain text"],
    "icon": "https://flagcdn.com/ae.svg"
  },
  {
    "code": "hy-AM",
    "language": "Armenian (Armenia)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/am.svg"
  },
  {
    "code": "as-IN",
    "language": "Assamese (India)",
    "support": ["Audio + human-labeled transcript"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "bn-IN",
    "language": "Bengali (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "my-MM",
    "language": "Burmese (Myanmar)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/mm.svg"
  },
  {
    "code": "zh-CN",
    "language": "Chinese (Simplified, China)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/cn.svg"
  },
  {
    "code": "zh-TW",
    "language": "Chinese (Mandarin, Taiwan)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/tw.svg"
  },
  {
    "code": "hr-HR",
    "language": "Croatian (Croatia)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/hr.svg"
  },
  {
    "code": "nl-NL",
    "language": "Dutch",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/nl.svg"
  },
  {
    "code": "en-IN",
    "language": "English (India)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "en-US",
    "language": "English (United States)",
    "support": ["Audio + human-labeled transcript", "Audio", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/us.svg"
  },
  {
    "code": "fi-FI",
    "language": "Finnish (Finland)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation"],
    "icon": "https://flagcdn.com/fi.svg"
  },
  {
    "code": "fr-FR",
    "language": "French",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/fr.svg"
  },
  {
    "code": "de-DE",
    "language": "German (Germany)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/de.svg"
  },
  {
    "code": "el-GR",
    "language": "Greek (Greece)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text"],
    "icon": "https://flagcdn.com/gr.svg"
  },
  {
    "code": "gu-IN",
    "language": "Gujarati (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "he-IL",
    "language": "Hebrew (Israel)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/il.svg"
  },
  {
    "code": "hi-IN",
    "language": "Hindi (India)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "is-IS",
    "language": "Icelandic (Iceland)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/is.svg"
  },
  {
    "code": "id-ID",
    "language": "Indonesian (Indonesia)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Pronunciation"],
    "icon": "https://flagcdn.com/id.svg"
  },
  {
    "code": "ga-IE",
    "language": "Irish (Ireland)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/ie.svg"
  },
  {
    "code": "it-IT",
    "language": "Italian (Italy)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/it.svg"
  },
  {
    "code": "ja-JP",
    "language": "Japanese (Japan)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/jp.svg"
  },
  {
    "code": "kn-IN",
    "language": "Kannada (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "km-KH",
    "language": "Khmer (Cambodia)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/kh.svg"
  },
  {
    "code": "ko-KR",
    "language": "Korean (Korea)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/kr.svg"
  },
  {
    "code": "ms-MY",
    "language": "Malay (Malaysia)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Pronunciation"],
    "icon": "https://flagcdn.com/my.svg"
  },
  {
    "code": "ml-IN",
    "language": "Malayalam (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "mr-IN",
    "language": "Marathi (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "mn-MN",
    "language": "Mongolian (Mongolia)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/mn.svg"
  },
  {
    "code": "ne-NP",
    "language": "Nepali (Nepal)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/np.svg"
  },
  {
    "code": "no-NO",
    "language": "Norwegian (Norway)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/no.svg"
  },
  {
    "code": "or-IN",
    "language": "Odia (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "fa-IR",
    "language": "Persian (Iran)",
    "support": ["Audio + human-labeled transcript", "Plain text"],
    "icon": "https://flagcdn.com/ir.svg"
  },
  {
    "code": "pl-PL",
    "language": "Polish (Poland)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/pl.svg"
  },
  {
    "code": "pt-PT",
    "language": "Portuguese (Portugal)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/pt.svg"
  },
  {
    "code": "pa-IN",
    "language": "Punjabi (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "ro-RO",
    "language": "Romanian (Romania)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation"],
    "icon": "https://flagcdn.com/ro.svg"
  },
  {
    "code": "ru-RU",
    "language": "Russian (Russia)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/ru.svg"
  },
  {
    "code": "sd-IN",
    "language": "Sindhi (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "es-ES",
    "language": "Spanish (Spain)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/es.svg"
  },
  {
    "code": "sv-SE",
    "language": "Swedish (Sweden)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/se.svg"
  },
  {
    "code": "ta-IN",
    "language": "Tamil (India)",
    "support": ["Audio + human-labeled transcript", "Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "te-IN",
    "language": "Telugu (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "th-TH",
    "language": "Thai (Thailand)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation"],
    "icon": "https://flagcdn.com/th.svg"
  },
  {
    "code": "tr-TR",
    "language": "Turkish (Turkey)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation", "Phrase list"],
    "icon": "https://flagcdn.com/tr.svg"
  },
  {
    "code": "ur-IN",
    "language": "Urdu (India)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/in.svg"
  },
  {
    "code": "vi-VN",
    "language": "Vietnamese (Vietnam)",
    "support": ["Audio + human-labeled transcript", "Plain text", "Structured text", "Output format", "Pronunciation"],
    "icon": "https://flagcdn.com/vn.svg"
  },
  {
    "code": "zu-ZA",
    "language": "Zulu (South Africa)",
    "support": ["Plain text"],
    "icon": "https://flagcdn.com/za.svg"
  }
]
''';
