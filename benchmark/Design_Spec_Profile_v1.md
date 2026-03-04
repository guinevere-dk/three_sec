규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. 하단 내비게이션 디자인은 Design_Spec_Library_Clips_v1 을 따른다.
3. 디자인을 따르는 것이지, 내부 기능까지 따라하는 것은 아니다.


<!DOCTYPE html>

<html class="light" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>3s - User Profile &amp; Settings</title>
<!-- Fonts -->
<link href="https://fonts.googleapis.com" rel="preconnect"/>
<link crossorigin="" href="https://fonts.gstatic.com" rel="preconnect"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;display=swap" rel="stylesheet"/>
<!-- Icons -->
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<!-- Tailwind CSS -->
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<!-- Theme Config -->
<script id="tailwind-config">
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        "primary": "#2badee",
                        "background-light": "#f6f7f8", // Soft off-white requested
                        "background-dark": "#101c22",
                    },
                    fontFamily: {
                        "display": ["Plus Jakarta Sans", "sans-serif"],
                        "sans": ["Plus Jakarta Sans", "sans-serif"]
                    },
                    borderRadius: {"DEFAULT": "0.5rem", "lg": "1rem", "xl": "1.5rem", "full": "9999px"},
                },
            },
        }
    </script>
<style>
        body {
            font-family: 'Plus Jakarta Sans', sans-serif;
            -webkit-font-smoothing: antialiased;
        }
        /* Custom scrollbar for cleaner look if content overflows */
        ::-webkit-scrollbar {
            width: 0px;
            background: transparent;
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-background-light dark:bg-background-dark text-slate-900 dark:text-white transition-colors duration-200">
<div class="relative flex h-full min-h-screen w-full flex-col max-w-md mx-auto overflow-x-hidden bg-background-light dark:bg-background-dark pb-20">
<!-- Top App Bar -->
<header class="sticky top-0 z-50 flex items-center justify-between px-4 py-3 bg-background-light/90 dark:bg-background-dark/90 backdrop-blur-md">
<button class="flex size-10 items-center justify-center rounded-full text-slate-900 dark:text-white hover:bg-slate-200 dark:hover:bg-slate-800 transition-colors">
<span class="material-symbols-outlined">arrow_back_ios_new</span>
</button>
<h2 class="text-lg font-bold leading-tight tracking-tight text-center flex-1">Profile</h2>
<button class="flex h-10 px-2 items-center justify-center rounded-lg text-primary font-bold text-base hover:bg-primary/10 transition-colors">
                Edit
            </button>
</header>
<!-- Profile Hero Section -->
<section class="flex flex-col items-center px-6 pt-4 pb-8">
<div class="relative mb-4">
<div class="bg-center bg-no-repeat bg-cover rounded-full h-28 w-28 ring-4 ring-white dark:ring-slate-800 shadow-lg" data-alt="Portrait of DongKwon Shin smiling" style='background-image: url("https://lh3.googleusercontent.com/aida-public/AB6AXuCMrh-3nxXLR19c0f6sWoJhVby_B60_D-zvuDb2_5Mgwt_2j_my3RCNWaABOeySYU9zniD07xQCcym5G3kLigbxUYUeY67ufh1LtZLS5AZCMNjGw5hFZ26jRLaAJCfWVGhXUvJKQUOMeva90V4uXzz0xTj3n_bWqCLm8kRG1Ouq2PZaZqccyEU0aGHttCDuDovW5V-u1sBOyueuzB_z2IebBoY8GuDAmvrd_CQEVWPNLp-VAa1j-BHVPznQoiMLa0VlGvTovnY6mQL1");'>
</div>
<!-- PRO Badge -->
<div class="absolute -bottom-2 -right-2 bg-gradient-to-br from-yellow-400 to-yellow-600 text-white text-xs font-bold px-3 py-1 rounded-full shadow-md border-2 border-white dark:border-slate-800 flex items-center gap-1">
<span class="material-symbols-outlined text-[14px]">verified</span>
                    PRO
                </div>
</div>
<h1 class="text-2xl font-bold text-slate-900 dark:text-white mb-1 tracking-tight">DongKwon Shin</h1>
<p class="text-slate-500 dark:text-slate-400 text-sm font-medium">Vlog Enthusiast • Seoul, KR</p>
</section>
<!-- Stats Dashboard -->
<section class="px-4 mb-8">
<div class="flex flex-wrap gap-3">
<!-- Stat 1 -->
<div class="flex-1 min-w-[100px] flex flex-col gap-1 rounded-2xl bg-white dark:bg-slate-800 p-4 items-center text-center shadow-sm border border-slate-100 dark:border-slate-700/50">
<p class="text-slate-900 dark:text-white text-2xl font-bold leading-none">124</p>
<p class="text-slate-500 dark:text-slate-400 text-xs font-semibold uppercase tracking-wide">Clips</p>
</div>
<!-- Stat 2 -->
<div class="flex-1 min-w-[100px] flex flex-col gap-1 rounded-2xl bg-white dark:bg-slate-800 p-4 items-center text-center shadow-sm border border-slate-100 dark:border-slate-700/50">
<p class="text-slate-900 dark:text-white text-2xl font-bold leading-none">12</p>
<p class="text-slate-500 dark:text-slate-400 text-xs font-semibold uppercase tracking-wide">Vlogs</p>
</div>
<!-- Stat 3 -->
<div class="flex-1 min-w-[100px] flex flex-col gap-1 rounded-2xl bg-white dark:bg-slate-800 p-4 items-center text-center shadow-sm border border-slate-100 dark:border-slate-700/50">
<p class="text-slate-900 dark:text-white text-2xl font-bold leading-none">4.2<span class="text-sm font-semibold text-slate-400 ml-0.5">GB</span></p>
<p class="text-slate-500 dark:text-slate-400 text-xs font-semibold uppercase tracking-wide">Used</p>
</div>
</div>
</section>
<!-- Management Group -->
<section class="px-4 mb-6">
<h3 class="text-xs font-bold text-slate-400 dark:text-slate-500 uppercase tracking-wider mb-2 ml-2">Management</h3>
<div class="bg-white dark:bg-slate-800 rounded-2xl overflow-hidden shadow-sm border border-slate-100 dark:border-slate-700/50">
<!-- Item 1 -->
<div class="group flex items-center justify-between p-4 cursor-pointer active:bg-slate-50 dark:active:bg-slate-700/50 border-b border-slate-100 dark:border-slate-700 transition-colors">
<div class="flex items-center gap-3.5">
<div class="flex items-center justify-center rounded-full bg-blue-50 dark:bg-slate-700 text-primary dark:text-blue-400 h-9 w-9">
<span class="material-symbols-outlined text-[20px]">cloud_sync</span>
</div>
<p class="text-slate-900 dark:text-white font-medium">Cloud Sync Status</p>
</div>
<div class="flex items-center gap-2">
<span class="text-green-500 font-medium text-sm flex items-center gap-1">
                            All backed up
                            <span class="material-symbols-outlined text-[16px] fill-1">check_circle</span>
</span>
<span class="material-symbols-outlined text-slate-300 dark:text-slate-600 text-xl">chevron_right</span>
</div>
</div>
<!-- Item 2 -->
<div class="group flex items-center justify-between p-4 cursor-pointer active:bg-slate-50 dark:active:bg-slate-700/50 transition-colors">
<div class="flex items-center gap-3.5">
<div class="flex items-center justify-center rounded-full bg-red-50 dark:bg-slate-700 text-red-500 dark:text-red-400 h-9 w-9">
<span class="material-symbols-outlined text-[20px]">delete</span>
</div>
<p class="text-slate-900 dark:text-white font-medium">Trash Bin</p>
</div>
<div class="flex items-center gap-2">
<span class="text-slate-400 text-sm">Empty</span>
<span class="material-symbols-outlined text-slate-300 dark:text-slate-600 text-xl">chevron_right</span>
</div>
</div>
</div>
</section>
<!-- Settings Group -->
<section class="px-4 mb-6">
<h3 class="text-xs font-bold text-slate-400 dark:text-slate-500 uppercase tracking-wider mb-2 ml-2">Settings</h3>
<div class="bg-white dark:bg-slate-800 rounded-2xl overflow-hidden shadow-sm border border-slate-100 dark:border-slate-700/50">
<!-- Item 1 -->
<div class="group flex items-center justify-between p-4 cursor-pointer active:bg-slate-50 dark:active:bg-slate-700/50 border-b border-slate-100 dark:border-slate-700 transition-colors">
<div class="flex items-center gap-3.5">
<div class="flex items-center justify-center rounded-full bg-purple-50 dark:bg-slate-700 text-purple-500 dark:text-purple-400 h-9 w-9">
<span class="material-symbols-outlined text-[20px]">hd</span>
</div>
<p class="text-slate-900 dark:text-white font-medium">Export Quality</p>
</div>
<div class="flex items-center gap-2">
<span class="text-primary font-semibold text-sm">1080p</span>
<span class="material-symbols-outlined text-slate-300 dark:text-slate-600 text-xl">chevron_right</span>
</div>
</div>
<!-- Item 2 -->
<div class="group flex items-center justify-between p-4 cursor-pointer active:bg-slate-50 dark:active:bg-slate-700/50 transition-colors">
<div class="flex items-center gap-3.5">
<div class="flex items-center justify-center rounded-full bg-orange-50 dark:bg-slate-700 text-orange-500 dark:text-orange-400 h-9 w-9">
<span class="material-symbols-outlined text-[20px]">notifications</span>
</div>
<p class="text-slate-900 dark:text-white font-medium">Notifications</p>
</div>
<div class="flex items-center gap-2">
<span class="material-symbols-outlined text-slate-300 dark:text-slate-600 text-xl">chevron_right</span>
</div>
</div>
</div>
</section>
<!-- Support Group -->
<section class="px-4 mb-8">
<h3 class="text-xs font-bold text-slate-400 dark:text-slate-500 uppercase tracking-wider mb-2 ml-2">Support</h3>
<div class="bg-white dark:bg-slate-800 rounded-2xl overflow-hidden shadow-sm border border-slate-100 dark:border-slate-700/50">
<!-- Item 1 -->
<div class="group flex items-center justify-between p-4 cursor-pointer active:bg-slate-50 dark:active:bg-slate-700/50 transition-colors">
<div class="flex items-center gap-3.5">
<div class="flex items-center justify-center rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 h-9 w-9">
<span class="material-symbols-outlined text-[20px]">help</span>
</div>
<p class="text-slate-900 dark:text-white font-medium">Help &amp; Feedback</p>
</div>
<div class="flex items-center gap-2">
<span class="material-symbols-outlined text-slate-300 dark:text-slate-600 text-xl">chevron_right</span>
</div>
</div>
</div>
</section>
<!-- Version Footer -->
<div class="text-center pb-8">
<p class="text-slate-400 dark:text-slate-600 text-xs font-medium">3s App Version 2.1.0</p>
</div>
<!-- Bottom Navigation (Mockup) -->
<div class="fixed bottom-0 w-full max-w-md bg-white/90 dark:bg-slate-900/90 backdrop-blur-lg border-t border-slate-200 dark:border-slate-800 pb-safe pt-2">
<div class="flex justify-around items-center px-4 h-16">
<button class="flex flex-col items-center gap-1 text-slate-400 hover:text-primary transition-colors">
<span class="material-symbols-outlined text-2xl">grid_view</span>
<span class="text-[10px] font-medium">Feed</span>
</button>
<button class="flex flex-col items-center gap-1 text-slate-400 hover:text-primary transition-colors">
<span class="material-symbols-outlined text-2xl">videocam</span>
<span class="text-[10px] font-medium">Record</span>
</button>
<button class="flex flex-col items-center gap-1 text-primary transition-colors">
<span class="material-symbols-outlined text-2xl fill-1">person</span>
<span class="text-[10px] font-medium">Profile</span>
</button>
</div>
</div>
</div>
</body></html>
