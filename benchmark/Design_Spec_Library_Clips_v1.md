규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. 하단 내비게이션 디자인은 Design_Spec_Library_Clips_v1 을 따른다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.


<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>3s - Finalized Album Detail View</title>
<script src="https://cdn.tailwindcss.com?plugins=forms,typography,container-queries"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/icon?family=Material+Icons+Round" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" rel="stylesheet"/>
<script>
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        primary: "#007AFF",
                        "background-light": "#F8F9FA",
                        "background-dark": "#121212",
                    },
                    fontFamily: {
                        display: ["Inter", "sans-serif"],
                    },
                    borderRadius: {
                        DEFAULT: "12px",
                    },
                },
            },
        };
    </script>
<style type="text/tailwindcss">
        body {
            font-family: 'Inter', sans-serif;
            -webkit-tap-highlight-color: transparent;
        }
        .grid-container {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 4px;
        }
        .thumbnail-aspect {
            aspect-ratio: 1 / 1;
        }
        .material-symbols-outlined {
            font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
        }
        .vlog-icon-active {
            font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-background-light dark:bg-background-dark text-slate-900 dark:text-slate-100 min-h-screen flex justify-center">
<div class="w-full max-w-[430px] bg-background-light dark:bg-background-dark min-h-screen shadow-2xl relative overflow-hidden flex flex-col">
<div class="h-12 w-full flex items-center justify-between px-6 bg-white dark:bg-neutral-900">
<span class="text-sm font-semibold">9:41</span>
<div class="flex items-center gap-1.5">
<span class="material-icons-round text-[18px]">signal_cellular_alt</span>
<span class="material-icons-round text-[18px]">wifi</span>
<span class="material-icons-round text-[18px]">battery_full</span>
</div>
</div>
<header class="bg-white dark:bg-neutral-900 px-4 py-3 border-b border-slate-100 dark:border-neutral-800 flex items-center justify-between sticky top-0 z-20">
<div class="flex items-center gap-3">
<button class="p-1 -ml-1">
<span class="material-icons-round text-slate-500">arrow_back_ios_new</span>
</button>
<h1 class="text-lg font-bold tracking-tight">Daily Life (일상) <span class="text-slate-400 font-normal ml-1">57</span></h1>
</div>
<div class="flex items-center">
<button class="text-primary font-semibold text-sm">Select All</button>
</div>
</header>
<main class="flex-1 overflow-y-auto p-1 bg-background-light dark:bg-background-dark">
<div class="grid-container">
<div class="relative thumbnail-aspect group">
<img alt="Pet dog video" class="w-full h-full object-cover rounded-xl border-4 border-primary" src="https://lh3.googleusercontent.com/aida-public/AB6AXuD7S9MsiMJ_QdIUKOQhqLnSuj7fa7YFJWvpW1JY9RHjxTwzBYpWdlRhov2EY1HZs_6qExqF1Asuy0HIKwD9z4u93leZDHyNRfI9SOhUYOeuEcSwW_hzMYQ7Edt8fm_krDbB04_qRgGDMKu_r9daoV3Ascw_ttduKXTKsmXFXbyMlhdi0WeeYNmIvD3FtEZVIeIS0c2TelqcBE4RuppV2bfYIPq3IrCg9VvmQgIs4rPHIqgo4ihvFVjFq9doUAZ14ZHYuF8yYJCBb0bU"/>
<div class="absolute top-2 right-2 bg-primary text-white w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shadow-md">1</div>
<div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:03</div>
</div>
<div class="relative thumbnail-aspect group">
<img alt="Cafe study video" class="w-full h-full object-cover rounded-xl border-4 border-primary" src="https://lh3.googleusercontent.com/aida-public/AB6AXuD8pehWOQUArJz_85qogDE8UX0t_0NrzGf4cC_8zx0dnHCMEnWOwmAlHwalKThGiIc6zvIsYRAs-jjoyZZn83DIBknC2rDAnDiOXPKKfdNknJRtTXCOyTo83L-TDH664Ux9nrN-L06jN_3kT7E8nXjhTy2Rj3Poan2YRSKwHiFx_N1IolczhoxJbT-nCnbgxs_t-qslvaC8LkDc2MxfQJ6DSKizUWOyKI4pOyEq3TymNWNC1XimhTH0y7OBjCQNQcCk62_zXhgnvxrb"/>
<div class="absolute top-2 right-2 bg-primary text-white w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shadow-md">2</div>
<div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:12</div>
</div>
<div class="relative thumbnail-aspect group">
<img alt="Coding workspace" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuAELZKRKe6jA9cORVKpTLr3hdZnB6So-0gr2n-8NZzhFHZJsYPqQkbH-nw7o2hTwMMmp5BLbn8Ug7Eh4E2FsOHgA6lhh89gCJc1M-78YG1rUO7Q0EcGilJwEbts_G66i41vu4P-eIXHFiJIu0Vojs0ifNJHuu3PRvHhd0cDd7lxxSoh2SM3cmzCmpqiymF34ISZBkp6FyC2WKgjf-iV2JsW1Qs5ZNK5khbOOYcdqQ-A_Qyo2Fyxk8I8UeRjZUEkSIM9mIMJPtkyGDlv"/>
<div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:08</div>
</div>
<div class="relative thumbnail-aspect group">
<img alt="Street photography" class="w-full h-full object-cover rounded-xl border-4 border-primary" src="https://lh3.googleusercontent.com/aida-public/AB6AXuATz5O9fzFSDjlcx51vV8GAejhJLWAQR64I3VEkpyu8Em6hj7prRQsGf6Gg5P6wz6sEx7a3PXtjzpzv7vb2rRfdO62OuMbSTYlo6_vbDiGJlXqYqgPprM0AGwd5k6bFXTVwZAf1K50Z2uby7DrYIqd-2-Waw0OpaXTmOUzE2dOp0Ob6Z1yAIQOcIH7yQZ2iCKEe1qJ4dvy3xlIIdsJt_yzdu276SOX8PqXNOh6a5UZiVuNbAH6-P2H0_1Xb_Z7cex_0gz85cnpfVE6I"/>
<div class="absolute top-2 right-2 bg-primary text-white w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shadow-md">3</div>
<div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:05</div>
</div>
<div class="relative thumbnail-aspect group">
<img alt="Delicious meal" class="w-full h-full object-cover rounded-xl border-4 border-primary" src="https://lh3.googleusercontent.com/aida-public/AB6AXuCpCZc3dXKbcQEUdH5wvP73jUEZU6DgPdsphdHOjMIEcZq0gdyv1xaR72ye__hhJwDk_IefeoNdVUbFjOoDIMD8NJQ5bXWe002UxH1KoXpRPQQxHRO1TzTQJSYM95EMWo_hDJkByDzJygKt8Nh7AyjgdisPCdWT9KTY8liFXwRHIZJDVk0l5tapaESS6wli0oUUhSYZRCMsN6sKm0TggzMRfxjxE6wtpRrJOd13oKWhyuNyfm_SQw2RtS46DTVEko_qYBlK_xIy72jd"/>
<div class="absolute top-2 right-2 bg-primary text-white w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shadow-md">4</div>
<div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:15</div>
</div>
<div class="relative thumbnail-aspect"><img alt="Food" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuB8mdT7h44xsU7aDPMuCJChOeBm7AoOI1r_k9jlVvocvds9zZCVDwKsfHWdGpTmXVjR99U7Z8pUvUETdOQ2d0OFoRDLjTvxgucrX6cXd0vvCA9-50LRHu0Hdli4XmvcNSNr66WiGnBVYUY01EXtjWUEaypLIFxPPTS0S2LOrq_nKbJcPCBg0_0tPGntgC0xt_pPril7m9lCfth8TWuJf38hiACP_UOBHYVQROGhmMUxBDdLhDoQS1Hluyw6ON-UCGJfXLqfmcfqaiv9"/><div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:04</div></div>
<div class="relative thumbnail-aspect"><img alt="Park" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuB5EKk9LxZhOTnble9z1VTzE0CD2S4yPFeosGhY7QbhuBgf7lbJrOXw18YLF8DPz2XDfyuHrdCUKG6ifVjr4GNGadbtq97-ANGJ3f8edMQbcih9CchYHMnd1_trwG8HZbiXMoZN4dxuIIogh2fCmJ9NUQYwkA-jdrHRErs2Vz20fJXLam9Vrnp1munjkkPpukdawRDMk4vA1OQZ3Y0JChsp-Q2CFeAuua_NFyyhgLYmOpbtmGHCtNSyNxK3hYg6t0FrNGqFi34l7eGi"/><div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:21</div></div>
<div class="relative thumbnail-aspect"><img alt="Sunset" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuCnM2NmJkZ0qwL7O_U_pAkNZMilK03NJMuMpUPvZGDYFgcheFedoGTkWQfle5IF1pjekfrqBhtaFj-bTvHKIEKb-CoIm_hbRSrt18ryCcuXj-Uo4B-45o38MHJ-yXoCCYqgJ0YPZ-ZRD2XZ5Gej4UAaKMd5iQE05YYn1Nv07OMeNpUvVJ2pBY0yO_Px46u1-q0gs2l90IhxcjAiSEP7Ch2DfV_35q5-0_3OULXiDwWyI3n2UUp3pZgeoatnPm97cA8Zvc0jH7-ICwRc"/><div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:06</div></div>
<div class="relative thumbnail-aspect"><img alt="Cityscape" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuBZBCoPZxIWdYR3eSKL6l3SqZTfk8DQSZ8d5idMxVUlBIBXO9Azz9U6xKfEa7_szrPzQ-pvkkbiCzC6Nb5DPT5akyOzG-yMV_8yMATaxDPJD2QdyAqdBKH6EcQ5xWIYD6OfKsCjQndtzo68Tu_uhpukHRuXT9baphQkNmLcKv4h0zXfHChy3IVKbqSRrY9qIIUFaZYqc2T5BIVqd5dxa6tfM1EHALWR_OUvYyzuCwfPxbAJCFx2vANidFy73SVKMy6-OlQLSiYViEU0"/><div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:10</div></div>
<div class="relative thumbnail-aspect"><img alt="Coffee shop" class="w-full h-full object-cover rounded-xl" src="https://lh3.googleusercontent.com/aida-public/AB6AXuCw8sjWO6BMRsyt2sCD9St8E3R0iSPAnQwW_kFQGoeUFLV72Omo-GLYagC1YAhKOqL_LALa-0JKXVm9f0eumkV5Dly8mv7hNW1BySpsLZwtmYmafjyzFlFJAwJXcgvi69rp-Ihk_WECgVD8dVaY0QH8FzQfdnYGDjm6RvA5s-vmvgS8A8ZPk8XRfe_6kntWXTbvhCCGJ8JWaQbGY68jo3rfGQZAWGTL1y5UWdWYZGhNymrEIIpYZTAicbHfPwg2Q3f4u63oRX-jHZU2"/><div class="absolute bottom-2 left-2 px-1.5 py-0.5 bg-black/40 backdrop-blur-md rounded text-[10px] text-white font-medium">0:02</div></div>
</div>
<div class="h-40"></div>
</main>
<div class="absolute bottom-24 left-1/2 -translate-x-1/2 w-[92%] bg-white/95 dark:bg-neutral-900/95 backdrop-blur-xl rounded-2xl shadow-2xl border border-white/20 dark:border-neutral-800/50 p-2 flex items-center justify-between z-30">
<div class="flex items-center">
<button class="w-12 h-12 flex items-center justify-center text-slate-400 dark:text-neutral-500 hover:text-primary active:scale-90 transition-transform">
<span class="material-icons-round text-[22px]">star_outline</span>
</button>
<button class="w-12 h-12 flex items-center justify-center text-slate-400 dark:text-neutral-500 hover:text-primary active:scale-90 transition-transform">
<span class="material-icons-round text-[22px]">content_copy</span>
</button>
</div>
<button class="flex flex-col items-center justify-center gap-0.5 bg-primary px-4 py-2 rounded-xl shadow-lg shadow-primary/30 active:scale-95 transition-transform">
<span class="material-icons-round text-white text-[22px]">movie</span>
<span class="text-[10px] font-bold text-white uppercase tracking-tight">Merge to Vlog</span>
</button>
<div class="flex items-center">
<button class="w-12 h-12 flex items-center justify-center text-slate-400 dark:text-neutral-500 hover:text-primary active:scale-90 transition-transform">
<span class="material-icons-round text-[22px]">folder_open</span>
</button>
<button class="w-12 h-12 flex items-center justify-center text-red-500/80 hover:text-red-500 active:scale-90 transition-transform">
<span class="material-icons-round text-[22px]">delete_outline</span>
</button>
</div>
</div>
<nav class="h-20 bg-white/80 dark:bg-neutral-900/80 backdrop-blur-md border-t border-slate-100 dark:border-neutral-800 flex items-center justify-around px-2 pb-5 z-20">
<button class="flex flex-col items-center justify-center gap-1 opacity-40">
<span class="material-symbols-outlined text-[26px]">video_call</span>
<span class="text-[10px] font-medium tracking-tight">Record</span>
</button>
<button class="flex flex-col items-center justify-center gap-1 text-primary">
<span class="material-symbols-outlined text-[26px]" style="font-variation-settings: 'FILL' 1">photo_library</span>
<span class="text-[10px] font-bold tracking-tight">Library</span>
</button>
<button class="flex flex-col items-center justify-center gap-1 opacity-40">
<span class="material-symbols-outlined text-[26px] vlog-icon-active">movie_filter</span>
<span class="text-[10px] font-medium tracking-tight">Vlog</span>
</button>
<button class="flex flex-col items-center justify-center gap-1 opacity-40">
<span class="material-symbols-outlined text-[26px]">account_circle</span>
<span class="text-[10px] font-medium tracking-tight">Profile</span>
</button>
</nav>
<div class="absolute bottom-1.5 left-1/2 -translate-x-1/2 w-32 h-1.5 bg-slate-200 dark:bg-neutral-800 rounded-full"></div>
</div>

</body></html>
