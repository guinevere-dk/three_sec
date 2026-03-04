규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. 하단 내비게이션 디자인은 Design_Spec_Library_Clips_v1 을 따른다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.

<!DOCTYPE html>
<html lang="ko"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>3s Album Library</title>
<link href="https://fonts.googleapis.com/css2?family=Pretendard:wght@400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<script src="https://cdn.tailwindcss.com?plugins=forms,typography,container-queries"></script>
<script>
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        primary: "#3B82F6",
                        folderYellow: "#FFD66B",
                        "app-bg": "#F4F6F8",
                    },
                    fontFamily: {
                        display: ["Pretendard", "sans-serif"],
                    },
                },
            },
        };
    </script>
<style type="text/tailwindcss">
        body {
            font-family: 'Pretendard', sans-serif;
            -webkit-tap-highlight-color: transparent;
            background-color: #F4F6F8;
        }
        .status-bar-safe {
            padding-top: env(safe-area-inset-top, 44px);
        }
        .bottom-nav-safe {
            padding-bottom: env(safe-area-inset-bottom, 34px);
        }
        ::-webkit-scrollbar {
            display: none;
        }
        .material-symbols-outlined {
            font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
        }
        .grid-item-scaled {
            transform: scale(0.8);
            transform-origin: center;
        }
    </style>
<style>
        body {
            min-height: max(884px, 100dvh);
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-[#F4F6F8] dark:bg-background-dark text-[#333333] dark:text-gray-100 transition-colors duration-200">
<div class="max-w-md mx-auto min-h-screen flex flex-col relative bg-[#F4F6F8] dark:bg-background-dark">
<header class="status-bar-safe px-6 pt-6 pb-2 flex justify-between items-end sticky top-0 bg-[#F4F6F8]/90 dark:bg-background-dark/80 backdrop-blur-md z-10">
<h1 class="text-xl font-bold tracking-tight">라이브러리</h1>
<div class="flex items-center space-x-2">
<button class="w-8 h-8 flex items-center justify-center text-[#FFD700]">
<span class="material-symbols-outlined text-[20px]">stars</span>
</button>
<button class="w-8 h-8 flex items-center justify-center text-black dark:text-white">
<span class="material-symbols-outlined text-[24px]">add</span>
</button>
</div>
</header>
<main class="flex-1 px-4 pt-4 pb-24 overflow-y-auto">
<div class="grid grid-cols-3 gap-x-2 gap-y-2">
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 rounded-2xl bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center">
<span class="material-symbols-outlined text-blue-500 text-[28px]">home</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">일상</p>
<p class="text-[11px] text-gray-400">24</p>
</div>
</div>
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 flex items-center justify-center">
<span class="material-symbols-outlined text-folderYellow text-[40px]">folder</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">가족</p>
<p class="text-[11px] text-gray-400">12</p>
</div>
</div>
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 flex items-center justify-center">
<span class="material-symbols-outlined text-folderYellow text-[40px]">folder</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">여행</p>
<p class="text-[11px] text-gray-400">48</p>
</div>
</div>
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 flex items-center justify-center">
<span class="material-symbols-outlined text-folderYellow text-[40px]">folder</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">맛집</p>
<p class="text-[11px] text-gray-400">15</p>
</div>
</div>
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 flex items-center justify-center">
<span class="material-symbols-outlined text-folderYellow text-[40px]">folder</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">업무</p>
<p class="text-[11px] text-gray-400">8</p>
</div>
</div>
<div class="flex flex-col items-center space-y-1 group active:scale-95 transition-transform duration-100 grid-item-scaled">
<div class="aspect-square w-full bg-white dark:bg-card-dark rounded-[22px] shadow-md shadow-gray-300/40 border border-transparent flex items-center justify-center relative overflow-hidden">
<div class="w-12 h-12 rounded-2xl bg-gray-50 dark:bg-gray-800 flex items-center justify-center">
<span class="material-symbols-outlined text-gray-500 text-[28px]">delete</span>
</div>
</div>
<div class="text-center w-full px-1">
<p class="font-semibold text-[13px] truncate">휴지통</p>
<p class="text-[11px] text-gray-400">2</p>
</div>
</div>
</div>
</main>
<nav class="fixed bottom-0 left-0 right-0 max-w-md mx-auto bg-white/95 dark:bg-black/90 backdrop-blur-xl border-t border-gray-100 dark:border-gray-800 bottom-nav-safe z-20">
<div class="flex justify-around items-center h-16 px-4">
<button class="flex flex-col items-center space-y-1 text-gray-400 dark:text-gray-500">
<span class="material-symbols-outlined text-[24px]">photo_camera</span>
<span class="text-[10px] font-medium">촬영</span>
</button>
<button class="flex flex-col items-center space-y-1 text-primary">
<span class="material-symbols-outlined text-[24px]">folder</span>
<span class="text-[10px] font-bold">라이브러리</span>
</button>
<button class="flex flex-col items-center space-y-1 text-gray-400 dark:text-gray-500">
<span class="material-symbols-outlined text-[24px]">play_circle</span>
<span class="text-[10px] font-medium">Vlog</span>
</button>
<button class="flex flex-col items-center space-y-1 text-gray-400 dark:text-gray-500">
<span class="material-symbols-outlined text-[24px]">person</span>
<span class="text-[10px] font-medium">프로필</span>
</button>
</div>
</nav>
</div>
<script>
        if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            document.documentElement.classList.add('dark');
        }
    </script>

</body></html>
