규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. 하단 내비게이션 디자인은 Design_Spec_Library_Clips_v1 을 따른다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.


<!DOCTYPE html>
<html class="light" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>3s Camera Capture</title>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<script>
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        primary: "#EF4444", // Red shutter color
                        "background-light": "#F8F9FA",
                        "background-dark": "#0A0A0A",
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
<style>.camera-viewfinder {
    aspect-ratio: 9/16;
    background-image: url(https://lh3.googleusercontent.com/aida-public/AB6AXuBI1WllkCbwPN8oZnGJNsLbBGjJ_tAhDOXmzqMzORsmmirhl56l5x5fnXzruZIp0rswNEdCtNgzbhTV9n-wli9kRbyOaBC-U_38uAhBYcVXe3FKHfQV49jlrmgUEeZRDLOshIhmOPQpg8wlrQ_uxz--82jqP6HyVgPjzYjAwwFwDz-KWTa3bNB9TxrtKLChPw9ZyB-DgLOKNdCLX7MDr2aNaBG2Wv6QUDfs_Xb9OxQd2Vu6ml0wBKQTzngdFnuQZJ7rg-jk7UtAfZt9);
    background-size: cover;
    background-position: center
    }
.material-symbols-outlined {
    font-variation-settings: "FILL" 0, "wght" 400, "GRAD" 0, "opsz" 24
    }
.shutter-ring {
    box-shadow: 0 0 0 4px white
    }</style>
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
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-black flex items-center justify-center min-h-screen font-display">
<div class="relative w-full max-w-[400px] aspect-[9/19] bg-black overflow-hidden shadow-2xl rounded-[3rem] border-[8px] border-zinc-800 flex flex-col">
<div class="relative w-full flex-1 camera-viewfinder flex flex-col justify-between p-6 overflow-hidden rounded-t-[2.5rem]">
<div class="flex justify-between items-start z-10 pt-4">
<div class="flex items-center">
<button class="h-10 px-3 flex items-center gap-2 rounded-full bg-black/40 backdrop-blur-md text-white border border-white/10 hover:bg-black/50 transition-colors">
<span class="material-symbols-outlined text-[18px]">wb_sunny</span>
<span class="text-xs font-medium">Daily Life</span>
<span class="material-symbols-outlined text-[16px] opacity-70">expand_more</span>
</button>
</div>
<div class="flex items-center gap-3">
<button class="w-10 h-10 flex items-center justify-center rounded-full bg-black/20 backdrop-blur-md text-white drop-shadow-lg">
<span class="material-symbols-outlined text-[20px]">flash_on</span>
</button>
<button class="w-10 h-10 flex items-center justify-center rounded-full bg-black/20 backdrop-blur-md text-white drop-shadow-lg">
<span class="material-symbols-outlined text-[20px]">settings</span>
</button>
</div>
</div>
<div class="flex flex-col items-center gap-6 pb-4 z-10 w-full mt-auto">
<div class="bg-black/40 backdrop-blur-xl border border-white/10 px-1 py-1 rounded-full flex items-center gap-1 mb-2">
<button class="w-8 h-8 flex items-center justify-center text-[10px] font-bold text-white/60 hover:text-white transition-colors">.5</button>
<button class="w-8 h-8 flex items-center justify-center text-[10px] font-bold bg-white text-black rounded-full">1</button>
<button class="w-8 h-8 flex items-center justify-center text-[10px] font-bold text-white/60 hover:text-white transition-colors">3</button>
</div>
<div class="w-full flex items-center justify-between px-6">
<div class="w-12 flex justify-center">
</div>
<div class="relative flex items-center justify-center">
<div class="shutter-ring w-20 h-20 rounded-full flex items-center justify-center transition-transform active:scale-95 duration-75 cursor-pointer">
<div class="bg-primary w-16 h-16 rounded-full"></div>
</div>
</div>
<div class="w-12 flex justify-center">
<button class="w-12 h-12 flex items-center justify-center rounded-full bg-black/20 backdrop-blur-md text-white drop-shadow-lg border border-white/10 active:bg-white/20 transition-colors">
<span class="material-symbols-outlined">flip_camera_ios</span>
</button>
</div>
</div>
</div>
</div>
<div class="w-full bg-white dark:bg-[#121212] border-t border-zinc-200 dark:border-zinc-800 pb-6 pt-2 z-20">
<div class="flex items-start justify-around px-2 h-14">
<div class="flex flex-col items-center gap-1 group cursor-pointer">
<span class="material-symbols-outlined text-primary">photo_camera</span>
<span class="text-[10px] font-medium text-primary">Capture</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-40 hover:opacity-100 transition-opacity cursor-pointer">
<span class="material-symbols-outlined dark:text-white">folder_open</span>
<span class="text-[10px] font-medium dark:text-white">Library</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-40 hover:opacity-100 transition-opacity cursor-pointer">
<span class="material-symbols-outlined dark:text-white">video_library</span>
<span class="text-[10px] font-medium dark:text-white">Vlog</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-40 hover:opacity-100 transition-opacity cursor-pointer">
<span class="material-symbols-outlined dark:text-white">person</span>
<span class="text-[10px] font-medium dark:text-white">Profile</span>
</div>
</div>
<div class="w-full flex justify-center mt-1">
<div class="w-32 h-1 bg-black/20 dark:bg-white/20 rounded-full"></div>
</div>
</div>
</div>
<div class="fixed top-4 right-4 hidden">
<button class="bg-zinc-800 text-white px-4 py-2 rounded-full text-sm font-medium shadow-xl flex items-center gap-2" onclick="document.documentElement.classList.toggle('dark')">
<span class="material-symbols-outlined text-sm">contrast</span>
        Switch Mode
    </button>
</div>
</body></html>
