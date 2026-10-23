# دەفتەری غیابات (ECPA)

سیستەمی تۆمارکردنی ئامادەبوون و غیاباتی خوێندکارانی زانکۆ بۆ چوار قۆنغ، لەسەر **Supabase**.

- **بەڕێوەبەر:** دەتوانێت بابەت، خوێندکار، مامۆستا و ڕێساکانی غیاب بەڕێوە ببات و هەموو تۆمارەکان ببینێت.
- **مامۆستا:** بە ئیمەیڵ و وشەی نهێنی خۆی دەچێتە ژوورەوە، و تەنها ئەو بابەت و شوعبانە دەبینێت کە بەڕێوەبەر بۆی دیاری کردووە.
- **ئینزاری خۆکار:** ئینزاری یەکەم، ئینزاری دووەم و ڕاسب بە غیاب. ڕێژەکان لە ڕێکخستن دەگۆڕدرێن.
- **ڕاپۆرت:** داگرتن بۆ Excel (CSV) و کۆپیکردنی خشتە.
- **ڕووکار:** کوردی، عەرەبی و ئینگلیزی، لەگەڵ مۆدی شەو و ڕۆژ.

## فایلەکان

| فایل | چییە |
|---|---|
| `index.html` | هەموو ئەپەکە لە یەک فایلدا |
| `supabase/migrations/…_ecpa_schema.sql` | خشتەکان و ڕێساکانی ئەمنی (RLS). پێشتر لە پڕۆژەی Supabase جێبەجێ کراوە |
| `supabase/functions/ecpa-teachers/index.ts` | Edge Function بۆ دروستکردن، گۆڕین و سڕینەوەی هەژماری مامۆستا. تەنها بەڕێوەبەر دەتوانێت بانگی بکات |

## چۆن بیکەمەوە؟

ڕیپۆکە Privateـە، بۆیە GitHub Pages بە خۆڕایی کار ناکات. دوو ڕێگا هەیە:

1. **خێرا:** `index.html` دابگرە و لە Chrome یان Edge بیکەرەوە.
2. **لینکی هەمیشەیی بە خۆڕایی:** بچۆ [Netlify](https://app.netlify.com)، [Vercel](https://vercel.com/new) یان Cloudflare Pages. **Import from GitHub** هەڵبژێرە، پاشان ڕیپۆی `ECPA`. Build command بەتاڵ بهێڵە و Publish directory بکە `/`. هەر جارێک کۆدەکە لێرە نوێ بکرێتەوە، ماڵپەڕەکەش خۆکار نوێ دەبێتەوە.

## چوونەژوورەوە

- **بەڕێوەبەر:** بە ئیمەیڵ و وشەی نهێنی هەژماری بەڕێوەبەر لە Supabase Auth.
- **مامۆستا:** بەڕێوەبەر لە داشبۆرد ← **مامۆستایان** ← **زیادکردنی مامۆستا** هەژمار دروست دەکات، و ئیمەیڵ و وشەی نهێنی دەدات بە مامۆستاکە.

ئەگەر وشەی نهێنی بەڕێوەبەرت لەبیرچوو: **Supabase Dashboard ← Authentication ← Users ←** ئیمەیڵەکەت ← **Send password recovery**.

## ئەمنیەت

کلیلی `anon` لە `index.html`دا بە مەبەست ئاشکرایە. ئەوەی کێ چی دەبینێت، **Row Level Security** لە ناو داتابەیسەکەدا بڕیاری لەسەر دەدات:

- کەسێک کە نەچووبێتە ژوورەوە هیچ نابینێت.
- مامۆستا تەنها ئەم شتانە دەبینێت و دەگۆڕێت:
  - ئەو بابەتانەی بۆی دیاری کراون
  - خوێندکارانی ئەو شوعبانە
  - تۆماری ئامادەبوونی وانەکانی خۆی
- تەنها بەڕێوەبەر دەتوانێت خوێندکار، بابەت، مامۆستا و ڕێکخستنەکان بگۆڕێت.
- هەژماری مامۆستا تەنها لە ڕێگەی Edge Functionـەوە دروست دەکرێت و پێویستی بە کلیلی `service_role` هەیە، کە هەرگیز ناچێتە ناو ئەپەکەوە.

## تێبینی

خشتە کۆنەکانی تاقیکردنەوە (`profiles`، `courses`، `students`، `attendance`، `teacher_courses`) هێشتا لە پڕۆژەکەدان، بەڵام ئەپەکە بەکاریان ناهێنێت. ئەگەر ویستت، لە **Table Editor**ـی Supabase بیانسڕەوە.

---

**English summary:** Single-file attendance register (`index.html`) backed by Supabase Auth + Postgres with Row Level Security. Admin manages everything; teachers sign in with email/password created by the admin through the `ecpa-teachers` Edge Function, and RLS limits each teacher to their assigned subject sections. Host `index.html` on any static host (Netlify, Vercel, Cloudflare Pages) or open it locally.
