규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. Edit 화면의 공통적인 디자인은 Design_Spec_Edit_Main_v1을 따른다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다. 

<!DOCTYPE html>
<html class="light" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>Compact AI Magic Tools</title>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<script id="tailwind-config">
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        "primary": "#2b8cee",
                        "premium-gold": "#D4AF37",
                        "background-light": "#f6f7f8",
                    },
                    fontFamily: {
                        "display": ["Inter", "sans-serif"]
                    },
                },
            },
        }
    </script>
<style type="text/tailwindcss">
        .ios-toggle {
            @apply relative inline-flex h-6 w-11 items-center rounded-full bg-gray-200 transition-colors duration-200;
        }
        .ios-toggle-dot {
            @apply inline-block h-5 w-5 transform rounded-full bg-white shadow-sm ring-0 transition duration-200 translate-x-0.5;
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="font-display bg-background-light min-h-screen">
<div class="relative mx-auto max-w-[430px] h-screen bg-slate-900 overflow-hidden flex flex-col justify-end">
<div class="absolute inset-0 z-0">
<div class="w-full h-full bg-cover bg-center opacity-80" style="background-image: url('https://lh3.googleusercontent.com/aida-public/AB6AXuCpr41nnifW-LewWtwOA5YjKAotgZvwtBxS-Xo73Avbmi3Y5Z3MdANJlEXU1tOTO9JjiSKgScty1_oKaH6MjV0-aVYeeBD0GmyXT4Yfnl7DSPGomgUwz0-A3QmXR8roqEg4wq9D5TN83m3_wmmZCvyUXAiJruSDgQeRUnwp3ORT2jZuyThYiatUDqHtDLlzqOYxyWuMFSyRqQfktOjUkKNmJ39jwXUi3jm2GlKvwDQdox2MWq5LXFaWiGfbWC9q1bJXBxUt0Q24Z2qP');"></div>
<div class="absolute inset-0 bg-black/40"></div>
</div>
<div class="z-10 bg-white rounded-t-[24px] shadow-2xl h-[40%] flex flex-col">
<div class="flex justify-center py-2">
<div class="h-1.5 w-10 rounded-full bg-gray-200"></div>
</div>
<div class="px-6 py-4 flex justify-between items-center">
<div>
<h2 class="text-[#0d141b] text-xl font-bold leading-tight">AI Magic Tools</h2>
</div>
<button class="text-gray-400 hover:text-gray-600">
<span class="material-symbols-outlined text-2xl">close</span>
</button>
</div>
<div class="flex-1 overflow-y-auto px-6 pb-6">
<div class="space-y-4">
<div class="flex items-center justify-between group">
<div class="flex items-center gap-4">
<div class="w-10 h-10 flex items-center justify-center bg-gray-50 rounded-xl">
<span class="material-symbols-outlined text-gray-700">palette</span>
</div>
<div class="flex flex-col">
<div class="flex items-center gap-2">
<span class="text-sm font-semibold text-gray-900">Auto Color</span>
<span class="px-1.5 py-0.5 text-[8px] font-bold bg-[#FAF3E0] text-[#B8860B] border border-[#EEDC82] rounded-[4px]">PRO</span>
</div>
<span class="text-xs text-gray-500">Enhance vibrancy instantly</span>
</div>
</div>
<div class="ios-toggle">
<span class="ios-toggle-dot"></span>
</div>
</div>
<div class="flex items-center justify-between group">
<div class="flex items-center gap-4">
<div class="w-10 h-10 flex items-center justify-center bg-gray-50 rounded-xl">
<span class="material-symbols-outlined text-gray-700">waves</span>
</div>
<div class="flex flex-col">
<div class="flex items-center gap-2">
<span class="text-sm font-semibold text-gray-900">Audio Cleanup</span>
<span class="px-1.5 py-0.5 text-[8px] font-bold bg-[#FAF3E0] text-[#B8860B] border border-[#EEDC82] rounded-[4px]">PRO</span>
</div>
<span class="text-xs text-gray-500">Remove noise, boost voice</span>
</div>
</div>
<div class="ios-toggle">
<span class="ios-toggle-dot"></span>
</div>
</div>
<div class="flex items-center justify-between group">
<div class="flex items-center gap-4">
<div class="w-10 h-10 flex items-center justify-center bg-gray-50 rounded-xl">
<span class="material-symbols-outlined text-gray-700 text-fill-1">auto_awesome</span>
</div>
<div class="flex flex-col">
<div class="flex items-center gap-2">
<span class="text-sm font-semibold text-gray-900">Video Denoise</span>
<span class="px-1.5 py-0.5 text-[8px] font-bold bg-[#FAF3E0] text-[#B8860B] border border-[#EEDC82] rounded-[4px]">PRO</span>
</div>
<span class="text-xs text-gray-500">Clear up grainy footage</span>
</div>
</div>
<div class="ios-toggle">
<span class="ios-toggle-dot"></span>
</div>
</div>
</div>
</div>
<div class="h-8 flex justify-center items-end pb-2">
<div class="w-32 h-1 bg-gray-200 rounded-full"></div>
</div>
</div>
</div>

</body></html>
