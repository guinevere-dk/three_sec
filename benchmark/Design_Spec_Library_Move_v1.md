규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.

<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>Move to Album Bottom Sheet</title>
<link href="https://fonts.googleapis.com" rel="preconnect"/>
<link crossorigin="" href="https://fonts.gstatic.com" rel="preconnect"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/icon?family=Material+Icons+Round" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@48,400,1,0" rel="stylesheet"/>
<script src="https://cdn.tailwindcss.com?plugins=forms,typography"></script>
<script>
      tailwind.config = {
        darkMode: "class",
        theme: {
          extend: {
            colors: {
              primary: "#3B82F6", // Bright Blue
              "background-light": "#FFFFFF",
              "background-dark": "#1C1C1E", // Dark gray/almost black for OLED feel
              "surface-light": "#F2F2F7",
              "surface-dark": "#2C2C2E",
              "divider-light": "#E5E5EA",
              "divider-dark": "#38383A",
            },
            fontFamily: {
              display: ["Inter", "sans-serif"],
              sans: ["Inter", "sans-serif"],
            },
            borderRadius: {
              DEFAULT: "0.5rem",
              "sheet": "1.5rem", // 24px
            },
            boxShadow: {
                'sheet': '0 -4px 20px rgba(0,0,0,0.1)',
            }
          },
        },
      };
    </script>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-gray-100 dark:bg-black font-sans antialiased h-screen w-full flex justify-center items-center overflow-hidden transition-colors duration-300">
<div class="relative w-full h-full max-w-md bg-background-light dark:bg-black shadow-2xl overflow-hidden flex flex-col">
<header class="flex items-center justify-between px-4 py-3 bg-background-light dark:bg-background-dark z-0 opacity-40">
<div class="flex items-center space-x-4">
<span class="material-icons-round text-2xl dark:text-white">grid_view</span>
<span class="material-icons-round text-2xl dark:text-white">close</span>
</div>
<h1 class="text-lg font-bold dark:text-white">2 Items Selected</h1>
<div class="flex items-center space-x-4">
<span class="material-icons-round text-yellow-500 text-2xl">play_circle</span>
<span class="material-icons-round text-2xl dark:text-white">check_box_outline_blank</span>
</div>
</header>
<div class="flex flex-1 overflow-hidden opacity-40">
<aside class="w-16 flex flex-col items-center py-4 space-y-8 border-r border-divider-light dark:border-divider-dark bg-background-light dark:bg-background-dark">
<div class="flex flex-col items-center space-y-1">
<span class="material-symbols-rounded text-primary text-2xl">folder</span>
<span class="text-[10px] text-gray-500 dark:text-gray-400">Daily</span>
</div>
<div class="flex flex-col items-center space-y-1 opacity-50">
<span class="material-symbols-rounded text-gray-400 dark:text-gray-500 text-2xl">folder</span>
<span class="text-[10px] text-gray-500 dark:text-gray-400">ffff</span>
</div>
<div class="flex flex-col items-center space-y-1 opacity-50">
<span class="material-symbols-rounded text-gray-400 dark:text-gray-500 text-2xl">delete</span>
<span class="text-[10px] text-gray-500 dark:text-gray-400">Trash</span>
</div>
</aside>
<main class="flex-1 overflow-y-auto bg-white dark:bg-black p-1">
<div class="grid grid-cols-3 gap-1">
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuCuQoL49hvB1Ey6J8zSXyMoFvNWxbe6LwKalXRXPapAOBSiZJZbRePf34AX82adR6kxzZ2Q0Z6K09LUWzJdxWE_qhcuHsu42HOYulBlfrZjAW5LagI4edofMcO-3cwkvfaRmsMy8b2cOz0YrhbpQmDDPSMu1-LEefSG5iNbWLFr5LNkttAIQBMeChcrn7w6Ff9edmjMYfjZ-S7KGCp25wVm8P0jMHW2U1TOm4et6jKIWxl90M5dzffBYEdznk2PYsJEqg14ltcaqabd"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white opacity-50"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuB4f4-hHddjriUFLPApUnB8Q9CAOKG1oN1Fii5RrRHSgMAZAf58VDqb5EkLHO-kOE6yEG05XwR2ZkXWJBaKMPOqfSuugI2IikpPcKN2zLyba_zNHkUzPuATTfLWyVf7V918b19Fj3lzmsukXzd6nT_abentk3YwT-_49v-cOLKyt6csMuzmlws6xJqlqI44Gsu3_l6L6AS29f6vFVkweftEcRA4dL4eytBPzwLISFXY-LH1VFWYOAw76l9fh_xOvLa4FrHBzZAEAokT"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white opacity-50"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuA3E5y7Z77tWv2LHUpbbyOoZzx0XseAQhf3RaPcZI0JEjlZa24-61G6mFYO5arx_MsGLMsbKnDZ3cfACbvELurbyigXXj3rNYe7UfH3k9EnsrB19H-J0Moix8geB37UQ3JCQcHgQOEzil3K4qidOfbgx40epPzTUoIZpyezWhJvBi9cDlxntdRr_AOEPe_Jv8vMGhYjlG9pUz9MQxzSaOtmpHdgElT8uZFvSJLIKoNnrBIPvpMFx6CLzQFi_m1mTHFVt3zFHpAeKaR5"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white opacity-50"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuAR50ofgdxe1eIaPkHhqysBqobbqQQhbAeocrypEU8o2wYLEV0pEOTg5HaKYvz63aPmZiqO1QNrW0mTso5i6WxPtyHmTwv2_Odpxkojbw_fX8wXFMOVXMpcOYiKn3ybTeZRq7SXbFqD7wrAtraeF_zt0wJfTwL5ekYsx6vjMRfeB0MrfXCPcfv8GszKUkaU8S7BH_Ck8OLQ2q4dkuJWtjZpxppRWE6m6IgNnCb0ITMagEIdXOjPpjHtmMdtElkBes6TmDwhdtrG6FNR"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white bg-primary"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuC0W7j4uyHhmfwKVCU0IX-1zMak7y0uEI0_VlLUx4AhOE1kEtgI0yqnJpNj3GTYgTGADqdZwhj9dADHwv1rlYOw3uEcFOWZxsdcEFUAy1RelHCt69nAsLlm2lYU84gcjdfo7oARAiQwBHrmuiniT5g4Cw34zVD0WktsoxVVKySoaQhQZriQNOSQuOH-cuJEQ6xQANTaB1aAaFclD5qh5Wia1fzgH4NAGCDyzGpgyuEWI0j9lq4d1XOL-qNR1DorJG4ZIp4OE28_NMxl"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white bg-primary"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuCmS8hpmbb6WKpjQQ2WhXAWShXge9pcll4qQFeOC9mvv0r7eZIxgEx5ObhdoZzeB_Y_qHggc-ZPq0u5hDl-lwj2z_MKLootFryWR4EnpQHMx6UWA9ndl4f5QPnssPqBx70k9ybu2s-JJwkvirbH5BCDJAmuOL-Ugz_sr-kYowxsZpV0fvTYNYwzssMYJ-7r4KPHu01n4xvQAN159-Lyb0yp2UTAe8DZZFUHTTNVm6njyGzKahxOR7ngtS2fCqLB2TB0dE5U7Meui_UH"/>
<div class="absolute bottom-1 right-1 w-4 h-4 rounded-full border border-white opacity-50"></div>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuC6mHt8ssMLA7xppfBXFfgUdyBOUq-M8lWMP2BPTSXeBYY8w7Vn-DB3KV2Vh3AE_NZWoooRdFufzO7jUPMipyq7JmTp8_OUZJk3bG8U3MyMFRWxkx9a3PWhbH5ojR-eHQkvo3Z5Qdosf1264wVltumwCnJ8CFsZpyCQoiLDMN21ofagFw4vydU_I2vbp8peuUIC600CsDNIn7vwrKmsna_ZoNvmmf44E609V5bhvTgyDqGQoJxnkI-cDTZ09AqV5FUrk2iQngjQdM-U"/>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuDCokywN60HySIxL8nGHHEwF5W_hnbf_5J77jqbRzuG8FalnAU_XDRCHKU82_l1WuBLS-j_vSTvvebm3wnns90sIhpkEhSEg2btS0NXVJO7GDhOJvCMOuYIHGDRrItT7Ii6XWfRkSM48v2SVQDMAHh9WQQbwUWnNb5E-2T9pBJ3x4txz6w5WFwmRmTFuYuMfAbrDgfjDFRuNB-rEIYii8LCt7vVhkiVqQypGc93NiLh0e8xYk2XjjFP4l62dWLpB9mIajyDXFcTFDM0"/>
</div>
<div class="aspect-square bg-gray-200 dark:bg-gray-800 relative">
<img alt="Gallery thumbnail" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuB02fHsp3nvBr3G2jmRVe1ApXUIL4c3nptWdwVAukQ1EWJCN04E3GED_33qIYxxtCfOGS0_ejSMEpkyyP8FSFq1QwMj3FQSt2Gay5i7oF4FVx8E0k1GYNeiXljTrZ2zWrfj-43f3ZvGqANOVSDtcWLsI4gffh3Pym64TzEnvqgjlnKXd-Ehj5VJBu0R7XV6Kz8CEUqGyp7TafY9F8o3eKin-4NHxC5w8gZEAjJViSaItiU0wrTO8F5c7kA3W0XkertSq6iecRWQpAhm"/>
</div>
</div>
</main>
</div>
<div class="absolute bottom-20 left-1/2 transform -translate-x-1/2 bg-white/90 dark:bg-gray-800/90 backdrop-blur-md rounded-full px-6 py-3 flex items-center space-x-8 shadow-lg z-0 opacity-40">
<span class="material-icons-round text-red-500 text-2xl">favorite</span>
<span class="material-icons-round text-primary text-2xl">drive_file_move</span>
<span class="material-icons-round text-green-600 text-2xl">content_copy</span>
<span class="material-icons-round text-red-400 text-2xl">delete</span>
</div>
<nav class="h-16 bg-background-light dark:bg-background-dark border-t border-divider-light dark:border-divider-dark flex justify-around items-center opacity-40">
<div class="flex flex-col items-center text-gray-400">
<span class="material-icons-round text-2xl">camera_alt</span>
<span class="text-[10px]">Shoot</span>
</div>
<div class="flex flex-col items-center text-primary">
<span class="material-symbols-rounded text-2xl fill-1">folder_open</span>
<span class="text-[10px]">Library</span>
</div>
<div class="flex flex-col items-center text-gray-400">
<span class="material-icons-round text-2xl">movie</span>
<span class="text-[10px]">Vlog</span>
</div>
<div class="flex flex-col items-center text-gray-400">
<span class="material-icons-round text-2xl">person</span>
<span class="text-[10px]">Profile</span>
</div>
</nav>
<div class="absolute inset-0 bg-black/60 z-40 transition-opacity duration-300"></div>
<div class="absolute bottom-0 left-0 w-full z-50 transform transition-transform duration-300 ease-out">
<div class="bg-background-light dark:bg-background-dark rounded-t-sheet shadow-sheet pb-8 flex flex-col max-h-[85vh]">
<div class="w-full flex justify-center pt-3 pb-1">
<div class="w-12 h-1.5 bg-gray-300 dark:bg-gray-600 rounded-full"></div>
</div>
<div class="px-6 py-4 flex items-center justify-between border-b border-transparent dark:border-divider-dark">
<h2 class="text-xl font-bold text-gray-900 dark:text-white">Move to...</h2>
<button class="p-2 -mr-2 text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-full transition-colors">
<span class="material-icons-round">close</span>
</button>
</div>
<div class="flex-1 overflow-y-auto">
<button class="w-full flex items-center px-6 py-4 hover:bg-gray-50 dark:hover:bg-surface-dark transition-colors group">
<div class="w-12 h-12 rounded-2xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center mr-4 group-hover:bg-blue-100 dark:group-hover:bg-blue-900/30 transition-colors">
<span class="material-icons-round text-primary text-3xl">add</span>
</div>
<div class="flex flex-col items-start">
<span class="text-primary font-bold text-lg">Create New Album</span>
</div>
</button>
<div class="mx-6 h-px bg-divider-light dark:bg-divider-dark my-1"></div>
<div class="flex flex-col pb-6">
<button class="w-full flex items-center justify-between px-6 py-3 hover:bg-gray-50 dark:hover:bg-surface-dark transition-colors">
<div class="flex items-center">
<div class="w-12 h-12 flex items-center justify-center mr-4">
<span class="material-symbols-rounded text-yellow-400 text-4xl" style="font-variation-settings: 'FILL' 1;">folder</span>
</div>
<div class="flex flex-col items-start text-left">
<span class="text-gray-900 dark:text-white font-semibold text-base">Daily Life</span>
<span class="text-gray-500 dark:text-gray-400 text-sm">124 clips</span>
</div>
</div>
<span class="material-icons-round text-gray-400 dark:text-gray-500">chevron_right</span>
</button>
<button class="w-full flex items-center justify-between px-6 py-3 hover:bg-gray-50 dark:hover:bg-surface-dark transition-colors">
<div class="flex items-center">
<div class="w-12 h-12 flex items-center justify-center mr-4">
<span class="material-symbols-rounded text-green-300 text-4xl" style="font-variation-settings: 'FILL' 1;">folder</span>
</div>
<div class="flex flex-col items-start text-left">
<span class="text-gray-900 dark:text-white font-semibold text-base">Travel</span>
<span class="text-gray-500 dark:text-gray-400 text-sm">85 clips</span>
</div>
</div>
<span class="material-icons-round text-gray-400 dark:text-gray-500">chevron_right</span>
</button>
<button class="w-full flex items-center justify-between px-6 py-3 hover:bg-gray-50 dark:hover:bg-surface-dark transition-colors">
<div class="flex items-center">
<div class="w-12 h-12 flex items-center justify-center mr-4">
<span class="material-symbols-rounded text-orange-300 text-4xl" style="font-variation-settings: 'FILL' 1;">folder</span>
</div>
<div class="flex flex-col items-start text-left">
<span class="text-gray-900 dark:text-white font-semibold text-base">Food</span>
<span class="text-gray-500 dark:text-gray-400 text-sm">42 clips</span>
</div>
</div>
<span class="material-icons-round text-gray-400 dark:text-gray-500">chevron_right</span>
</button>
<button class="w-full flex items-center justify-between px-6 py-3 hover:bg-gray-50 dark:hover:bg-surface-dark transition-colors">
<div class="flex items-center">
<div class="w-12 h-12 flex items-center justify-center mr-4">
<span class="material-symbols-rounded text-purple-300 text-4xl" style="font-variation-settings: 'FILL' 1;">folder</span>
</div>
<div class="flex flex-col items-start text-left">
<span class="text-gray-900 dark:text-white font-semibold text-base">ffff</span>
<span class="text-gray-500 dark:text-gray-400 text-sm">3 clips</span>
</div>
</div>
<span class="material-icons-round text-gray-400 dark:text-gray-500">chevron_right</span>
</button>
</div>
</div>
</div>
</div>
</div>

</body></html>
