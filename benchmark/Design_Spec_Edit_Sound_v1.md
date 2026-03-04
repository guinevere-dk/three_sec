규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. Edit 화면의 공통적인 디자인은 Design_Spec_Edit_Main_v1을 따른다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.

<!DOCTYPE html>
<html class="light" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>3s Video Edit Studio - Compact Audio Mixer</title>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com" rel="preconnect"/>
<link crossorigin="" href="https://fonts.gstatic.com" rel="preconnect"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&amp;display=swap" rel="stylesheet"/>
<script id="tailwind-config">
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        "primary": "#2b8cee",
                        "background-light": "#F4F6F8",
                        "background-dark": "#101922",
                        "text-primary-light": "#0d141b",
                        "text-primary-dark": "#ffffff",
                        "text-secondary-light": "#4c739a",
                        "text-secondary-dark": "#94a3b8",
                    },
                    fontFamily: {
                        "display": ["Inter", "sans-serif"]
                    },
                    borderRadius: { "DEFAULT": "0.25rem", "lg": "0.5rem", "xl": "0.75rem", "full": "9999px" },
                },
            },
        }
    </script>
<style type="text/tailwindcss">
        .scrollbar-hide::-webkit-scrollbar {
            display: none;
        }
        .scrollbar-hide {
            -ms-overflow-style: none;
            scrollbar-width: none;
        }
        input[type="range"] {
            -webkit-appearance: none;
            @apply bg-gray-200/50 dark:bg-gray-700/50 h-[3px] rounded-full outline-none transition-all;
        }
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            @apply size-5 bg-white border-2 border-primary rounded-full shadow-md cursor-pointer active:scale-110 transition-transform;
        }
    </style>
<style>
        body {
            min-height: 100dvh;
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-background-light dark:bg-background-dark font-display antialiased">
<div class="relative flex h-screen w-full flex-col overflow-hidden max-w-md mx-auto shadow-2xl bg-background-light dark:bg-background-dark">
<header class="flex items-center justify-between p-4 z-20 bg-background-light/95 dark:bg-background-dark/95 backdrop-blur-sm sticky top-0 border-b border-gray-100 dark:border-gray-800">
<div class="flex items-center gap-0.5">
<button class="p-2 text-text-primary-light dark:text-text-primary-dark hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition-colors">
<span class="material-symbols-outlined text-2xl">close</span>
</button>
<button class="p-2 text-text-primary-light dark:text-text-primary-dark hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition-colors">
<span class="material-symbols-outlined text-xl">undo</span>
</button>
<button class="p-2 text-text-primary-light dark:text-text-primary-dark opacity-40 cursor-not-allowed">
<span class="material-symbols-outlined text-xl">redo</span>
</button>
</div>
<h1 class="text-text-primary-light dark:text-text-primary-dark text-[15px] font-bold leading-tight tracking-tight flex-1 text-center truncate px-2">
                Untitled Project
            </h1>
<div class="flex items-center gap-1">
<button class="relative flex items-center justify-center p-2 rounded-full hover:bg-black/5 dark:hover:bg-white/10 transition-colors group">
<span class="material-symbols-outlined text-text-primary-light dark:text-text-primary-dark">auto_fix_high</span>
<span class="absolute -top-0.5 -right-0.5 flex h-4 w-4 items-center justify-center rounded-full bg-amber-400 text-[9px] font-black text-black border border-white dark:border-background-dark">AI</span>
</button>
<button class="ml-1 px-4 py-1.5 rounded-full bg-primary text-white text-sm font-bold leading-normal shadow-sm hover:bg-primary/90 transition-colors">
                    Done
                </button>
</div>
</header>
<main class="flex-1 flex flex-col justify-center items-center relative w-full overflow-hidden px-4 py-6">
<div class="relative w-full max-w-[220px] aspect-[9/16] rounded-2xl overflow-hidden shadow-2xl bg-black group">
<div class="absolute inset-0 bg-cover bg-center" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuAkJjtxH4vFMPA4pUL1TBViCYbidaJ4f8uTUqwg3iW9vtw48jvZdJ7tMJ6D6kLG5DER1lya2cWkd08P7rY2W34sItvuIo6q8RWa1htqdI5R817qSIoymaQ_7S2nFLT-FJvqzeh8viIzYHAdEwBgH5NwNUVtDE9GsBHkf5dzMa73zpqaKyKDRmiEx3NMvQWajPEz8SNEmGZ3oWCmk0B6jlHNNVaqTZqXPOTJs-ug2aCHrgS8IMNZuvkcBUK3_-tyFyFpFgoVCM6DM7MT");'></div>
<div class="absolute inset-0 bg-gradient-to-b from-black/20 via-transparent to-black/40 pointer-events-none"></div>
<button class="absolute inset-0 m-auto flex items-center justify-center size-14 rounded-full bg-white/20 backdrop-blur-sm text-white hover:bg-white/30 transition-all">
<span class="material-symbols-outlined text-3xl fill-current">play_arrow</span>
</button>
<div class="absolute bottom-4 left-4 right-4 flex flex-col gap-1.5">
<div class="flex items-center justify-between text-[10px] font-bold text-white tracking-wide">
<span>0:04</span>
<span>0:15</span>
</div>
<div class="h-1.5 w-full bg-white/30 rounded-full overflow-hidden">
<div class="h-full bg-white w-1/3 rounded-full shadow-[0_0_8px_rgba(255,255,255,0.8)]"></div>
</div>
</div>
</div>
</main>
<div class="w-full px-0 py-2">
<div class="flex items-center justify-center mb-1">
<div class="w-1 h-4 bg-primary rounded-full"></div>
</div>
<div class="flex overflow-x-auto scrollbar-hide px-4 gap-1 snap-x snap-mandatory">
<div class="shrink-0 snap-center relative size-12 rounded-lg overflow-hidden border border-transparent opacity-60">
<div class="absolute inset-0 bg-cover bg-center" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuBIMXfNWy8IP9hUWuQXgvk3h5-0R-wR-rMT3fDsKf6XiJdza4w1rdJoQCaq0Wc0xNMXS97YIX6F9vH1JgeQFWoab1GMVNRbFDJ0RyT2TcbVWsFxCaporiZGEn1e3dzaYgQR6moVSVONqRN6SY-OsNETlOL5P3HHZlQ4ZUqC0v3ePjIMjZijbOtmd8-vSDhwGSgdMNcNO9EaqFlSQRgMAcIl-Y-c0wbWQrWK0rtVhT9fJ-mvz-0X6MkhYsqR63ynLPjeVzY4ZM1kJDhz");'></div>
</div>
<div class="shrink-0 snap-center relative size-12 rounded-lg overflow-hidden ring-2 ring-primary ring-offset-2 ring-offset-background-light dark:ring-offset-background-dark z-10 shadow-lg scale-105">
<div class="absolute inset-0 bg-cover bg-center" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuAGT2knCeorW3-il1QfczSr1R0-ywVaNL1X6j5kOxzEFmSH2o07iJ8JCay98CR9IAMD_YIBox9AyFf64PyHpINzhTvPOprvbWj4kzFxgrqTeVkiRUkfVKKTFsIZEaIF5U-ONFSdOk3hWS3NGQgn15prUC69PrRH5NF2UZ1COjVYbtrfmAw6EyBsfApZ-v___p9ZMBxPNQusBk6sJ7nurbCALvvGzXJ3TCTRERgFgG7LspncX-3eR_j0Yw9ykl-mRThc-P4JlwktDFa1");'></div>
</div>
<div class="shrink-0 snap-center relative size-12 rounded-lg overflow-hidden border border-transparent opacity-60">
<div class="absolute inset-0 bg-cover bg-center" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuBhOsc5oh15uqKp0j4XVVBveaFnR5Wy4iUR8ivPNej-kaIRrVNLmxvfVX1VSzp_PhJROIGnvSNmHl3WUlSPMy4QIr59np2b3Mfbw0pfIZ0V-ge9XRuE7B1cmlEFa1gFHc9Emyj8TRNQZDOsJ0hx7zL7h9CiJ3QPzA0nAFkkSKUg0iZglv3KRy0XJwjd7-9tXrOuIaMJr5xU7PoNxBpsTG9etDvqEdmtURLzrhZ_Ckoz6BCtvxYtcRZOg7Ulyz9dO9RE-iGDeB5cT8bA");'></div>
</div>
<div class="shrink-0 snap-center relative size-12 rounded-lg overflow-hidden border border-transparent opacity-60">
<div class="absolute inset-0 bg-cover bg-center" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuD5XWYwrjpAqGcBLzdgwwV9JdqN1YVybTH5BFliV10y9FfPsIBncQlH6uHUBChO-pwgj_ERFjzR0YAi1hDMRX0lAJ1-gtXHFTfDfbvixkyDJXt3iCtZKjSjJ31krbXtJTOd58o0TnaNnSkqvPB4Sk_jgK23gtXZex1XYrHyicOYngSL495H8QPQFmSY7uB-vK7y9zy8qSF8xIPqaIG4jIG9PPvc3gmW0u2AKV_01QrWjBMZmVJy5-uXZ6XAGoVl6tii-IHdUPfTrdc_");'></div>
</div>
<button class="shrink-0 snap-center flex items-center justify-center size-12 rounded-lg border border-dashed border-gray-300 dark:border-gray-700 text-text-secondary-light bg-white/50 dark:bg-black/20">
<span class="material-symbols-outlined text-sm">add</span>
</button>
</div>
</div>
<div class="w-full flex flex-col bg-white dark:bg-gray-900 z-20 pb-safe pt-6 px-6 rounded-t-[32px] border-t border-gray-100 dark:border-gray-800 shadow-[0_-10px_30px_rgba(0,0,0,0.06)]">
<div class="flex items-center justify-between mb-6">
<div class="flex flex-col">
<h3 class="text-[12px] font-black uppercase tracking-widest text-text-secondary-light dark:text-text-secondary-dark mb-1">Audio Mixer</h3>
<div class="h-1 w-6 bg-primary/20 rounded-full"></div>
</div>
<div class="flex gap-4">
<button class="text-text-secondary-light dark:text-text-secondary-dark text-[14px] font-semibold hover:opacity-70">Reset</button>
<button class="text-primary text-[14px] font-bold hover:opacity-70">Apply</button>
</div>
</div>
<div class="flex flex-col gap-6 pb-8">
<div class="flex items-center gap-4">
<div class="flex items-center gap-2 min-w-[100px]">
<div class="size-8 flex items-center justify-center rounded-xl bg-gray-50 dark:bg-gray-800">
<span class="material-symbols-outlined text-text-primary-light dark:text-text-primary-dark text-lg">graphic_eq</span>
</div>
<span class="text-[13px] font-bold text-text-primary-light dark:text-text-primary-dark">Original</span>
</div>
<div class="flex-1 flex items-center px-2">
<input class="w-full" max="100" min="0" type="range" value="75"/>
</div>
<div class="min-w-[40px] text-right">
<span class="text-[13px] font-black text-primary tabular-nums">75%</span>
</div>
</div>
<div class="flex items-center gap-4">
<div class="flex items-center gap-2 min-w-[100px]">
<div class="size-8 flex items-center justify-center rounded-xl bg-gray-50 dark:bg-gray-800">
<span class="material-symbols-outlined text-text-primary-light dark:text-text-primary-dark text-lg">music_note</span>
</div>
<span class="text-[13px] font-bold text-text-primary-light dark:text-text-primary-dark">BGM</span>
</div>
<div class="flex-1 flex items-center px-2">
<input class="w-full" max="100" min="0" type="range" value="40"/>
</div>
<div class="min-w-[40px] text-right">
<span class="text-[13px] font-black text-primary tabular-nums">40%</span>
</div>
</div>
</div>
</div>
</div>

</body></html>
