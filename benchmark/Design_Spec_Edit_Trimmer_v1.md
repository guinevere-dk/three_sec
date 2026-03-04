규칙
1. 벤치마킹 이미지이므로 모든 이미지들의 공통적인 기능에 대한 디자인이 약간씩 다르다.
2. 해당 디자인처럼 우리 앱도 편집 중에는 하단 내비게이션을 숨기도록 한다.
3. 디자인을 따르는 것이지, 글자나 내부 기능까지 따라하는 것은 아니다.
4. 글자, 내부 기능은 현재 앱 그대로 유지한다.

<!DOCTYPE html>
<html class="light" lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>Precision Clip Trimmer - 3s App</title>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&amp;display=swap" rel="stylesheet"/>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<script id="tailwind-config">
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        "primary": "#f2f20d",
                        "background-light": "#F8F9FA",
                        "background-dark": "#121212",
                    },
                    fontFamily: {
                        "display": ["Inter", "sans-serif"]
                    },
                    borderRadius: {
                        "DEFAULT": "0.25rem",
                        "lg": "0.5rem",
                        "xl": "0.75rem",
                        "2xl": "1.25rem",
                        "3xl": "1.75rem",
                        "full": "9999px"
                    },
                    boxShadow: {
                        'glow': '0 0 15px rgba(242, 242, 13, 0.3)',
                    }
                },
            },
        }
    </script>
<style>
        .no-scrollbar::-webkit-scrollbar {
            display: none;
        }
        .no-scrollbar {
            -ms-overflow-style: none;
            scrollbar-width: none;
        }
        body {
            min-height: 100dvh;
        }
        .material-symbols-outlined {
            font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
        }
        .fill-1 {
            font-variation-settings: 'FILL' 1;
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-[#F8F9FA] dark:bg-[#121212] font-display text-gray-900 dark:text-white antialiased overflow-hidden selection:bg-primary selection:text-black">
<div class="relative flex h-screen w-full flex-col max-w-md mx-auto bg-[#F8F9FA] dark:bg-[#121212] shadow-2xl overflow-hidden">
<header class="flex items-center justify-between px-4 py-3 z-50">
<button class="text-gray-900 dark:text-white flex size-10 items-center justify-center rounded-full hover:bg-black/5 transition-colors">
<span class="material-symbols-outlined text-2xl">close</span>
</button>
<h2 class="text-gray-900 dark:text-white text-[17px] font-semibold">Untitled Project</h2>
<div class="flex items-center gap-2">
<button class="flex items-center justify-center p-2 rounded-full hover:bg-black/5 transition-colors">
<span class="material-symbols-outlined text-[24px]">auto_fix_high</span>
</button>
<button class="flex items-center justify-center px-5 py-2 rounded-full bg-[#007AFF] text-[15px] font-semibold text-white hover:opacity-90 transition-opacity">
                    Done
                </button>
</div>
</header>
<main class="flex-1 flex flex-col items-center justify-center px-4 pt-2 relative z-0">
<div class="relative w-full aspect-[9/16] rounded-3xl overflow-hidden shadow-xl bg-black group">
<img alt="Portrait video of a woman looking at sunset" class="w-full h-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuBMDTK1UaeEHNB5IA6FXD3l0S95P9VL_widX4v-1IeZlIeBxgPala7JFHf08akTCU_Yxu_laic99wQF44_5ANkpA_5SeZ-Tkpf4XBQuHb2fyRFofYUFMkt4I_xk8HVy77i0X-xMLm2e6mvFrH-xaGA5iEDMlKhjod7E6OCvzM0RIg7qdPF1GZdu2942ctNrXBc7cPKf2Hu1QTeoncFRG_olvj2qiwnqxxT9_r-CKuFaK6pVqAuqSbUZMWz4vhvdt1xCXU0eVAROaqAx"/>
<div class="absolute inset-0 flex items-center justify-center pointer-events-none">
<div class="w-16 h-16 bg-white/10 backdrop-blur-md rounded-full flex items-center justify-center border border-white/20">
<span class="material-symbols-outlined text-white text-4xl ml-1 fill-1">play_arrow</span>
</div>
</div>
<div class="absolute bottom-6 left-0 right-0 px-6 flex items-center gap-4">
<div class="flex-1">
<div class="flex items-center justify-between text-[10px] text-white/80 font-medium mb-1.5">
<span>0:04</span>
<span>0:15</span>
</div>
<div class="h-1 w-full bg-white/20 rounded-full overflow-hidden">
<div class="h-full bg-white w-1/3 rounded-full"></div>
</div>
</div>
<button class="size-10 rounded-full bg-black/40 backdrop-blur-md border border-white/20 flex items-center justify-center text-white hover:bg-black/60 transition-colors">
<span class="material-symbols-outlined text-[22px]">crop_landscape</span>
</button>
</div>
</div>
</main>
<section class="flex flex-col w-full px-4 pt-6 pb-10 z-40">
<div class="relative w-full flex items-center gap-2">
<div class="shrink-0 w-12 h-16 rounded-xl overflow-hidden opacity-40 blur-[1px]">
<img alt="prev clip" class="h-full w-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuACHMA4EYI_9sUE2sqZN05T9sC50r7Y0bsGbQ4NrVbanCdfFIEU7gBo37m85cKojeWdTn2Klko1pbxta1PtFJxIl6y4XYnx8InH6ylYHG2_A6MnoyEup2I2ADbJnJFjenQau726gG4BAh4FFZJAtls3mbe0LNhFIlwpIW3GhQBikOi4XWbr_8bJwdgAo7sXWLnaNnbe-O2aO2c3YR_s6clnlH8_jiiKOe4ynsjYVq3EOuOdR1qhWtEs1Erj-zCzOHis4rYl6tqiHUuG"/>
</div>
<div class="relative flex-1 h-16 flex items-center">
<div class="absolute -top-24 left-[20%] z-50 transform -translate-x-1/2 flex flex-col items-center">
<div class="w-20 h-20 rounded-full border-4 border-primary bg-gray-900 overflow-hidden shadow-glow relative">
<div class="absolute inset-0 w-full h-full bg-cover bg-center scale-[200%]" style="background-image: url('https://lh3.googleusercontent.com/aida-public/AB6AXuC-DeTGnzozBJ5tPkNPbvRjekPa6RBJ0OYRZWXopwny6sOkSYPMTuXfQJXNLQHV-ZDGn6idxKk2ZkWt2p8QTvfDClAvp_-yY7okLFZpwpRPYR5T8C5eXQL0PR5EvWv-n_F4s-ViY8ndvk4s0wDAKDMnLu-swlqarDT1duXdpW_Vmlaw4Rra2BDzaO_GUpodW10Lz6as80-xZZrS5cQRN3W9k-6YsyEaTOOPVswYug7CDy3rOO56l6Cm2AQx4Pshb0jIsFy_FD1akmCq'); background-position: 20% 50%;"></div>
<div class="absolute inset-0 flex items-center justify-center pointer-events-none">
<div class="w-0.5 h-full bg-white/80"></div>
</div>
</div>
<div class="w-0 h-0 border-l-[8px] border-l-transparent border-r-[8px] border-r-transparent border-t-[8px] border-t-primary mt-[-2px]"></div>
</div>
<div class="relative w-full h-full bg-black/5 dark:bg-white/5 rounded-xl overflow-hidden flex">
<div class="flex h-full w-full opacity-60">
<img alt="frame" class="h-full w-1/4 object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuACHMA4EYI_9sUE2sqZN05T9sC50r7Y0bsGbQ4NrVbanCdfFIEU7gBo37m85cKojeWdTn2Klko1pbxta1PtFJxIl6y4XYnx8InH6ylYHG2_A6MnoyEup2I2ADbJnJFjenQau726gG4BAh4FFZJAtls3mbe0LNhFIlwpIW3GhQBikOi4XWbr_8bJwdgAo7sXWLnaNnbe-O2aO2c3YR_s6clnlH8_jiiKOe4ynsjYVq3EOuOdR1qhWtEs1Erj-zCzOHis4rYl6tqiHUuG"/>
<img alt="frame" class="h-full w-1/4 object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuA-Qvj9Kf93iYtof91ZAAU_yfq7NuJSmlTPA7x5SI2m8RbGHj2DKqBStfCRRavnr-s7oyXJ884GIFsG9j71WUxMapx8_kGxA1f4W-cEr_r7uGYsAp4jwq1lO6p1BbfZFKPLL9Q8m430_BjfdVrsOi_EqD6zDkjMbp1A3RL1qMDEbA1YHJqVWt8xhbIxOLZSGvzV2IT3rzq60MIz7pAzgXq9bdRt7JKaK4CZUIaCzEYvs38U9XUSv62K5VbA4bDNLa4e3OV2djcQroo4"/>
<img alt="frame" class="h-full w-1/4 object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuBesfx5kB_yIyULSS1urdU13U-WRZ42_ZUwdiNH7XOp-eAcF_iTiA5ltoiX3t7_7qWHS5RzKLWY5kHirzeZTFhh3aCFlLboLdu4DLU1iP2qs8KKkhMjR6-VXDy2lmAzYqGgVr_LXkvf-5cocPgzvoFp7JVR23AZa66tjY48r7mh53KoUX8cSjZLzzndF0XUSYd7xsXfY5aRpW47u24BxcdWdir2ou82Cy_EIZMNAYCRSP-foHxjDztJ8DTUGDe4qfoXuX4gAMHFJi6c"/>
<img alt="frame" class="h-full w-1/4 object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuATm27_9CNHEAQNA6nSiFs5BxmVPpFnK2muVsN0JHGbWviBzGIuko8HN1dmt_3ah1ixkxPGFtpkR4u0mW9PVP8ACRP30osP5iX2PwhQCU-EwNIVcPyYN5Juc-cyitLI4kpzFv9tBrgt9O6ZPYHli-y3HfHpSTyPyEQOCISMq36ziY-yjOQyRKr7AxEptAIVsRFtEWErZ17C2n4oPzAGtvtYs4Me68BMeMRbQsPabDOvLBojalA2JcPGNS0_0HpUiZAlo2A43SBMudhc"/>
</div>
<div class="absolute inset-0 flex">
<div class="w-[20%] h-full bg-black/60 backdrop-blur-[2px]"></div>
<div class="flex-1 h-full border-y-[3px] border-primary relative">
<div class="absolute left-1/3 top-0 bottom-0 w-0.5 bg-white shadow-sm z-10"></div>
</div>
<div class="w-[15%] h-full bg-black/60 backdrop-blur-[2px]"></div>
</div>
<div class="absolute left-[20%] top-0 bottom-0 w-5 -ml-2.5 z-20 flex flex-col items-center justify-center cursor-col-resize">
<div class="w-full h-full bg-primary rounded-l-md shadow-md flex items-center justify-center">
<div class="w-[2px] h-3 bg-black/20 rounded-full mx-[1px]"></div>
<div class="w-[2px] h-3 bg-black/20 rounded-full mx-[1px]"></div>
</div>
</div>
<div class="absolute right-[15%] top-0 bottom-0 w-5 -mr-2.5 z-20 flex flex-col items-center justify-center cursor-col-resize">
<div class="w-full h-full bg-primary rounded-r-md shadow-md flex items-center justify-center">
<div class="w-[2px] h-3 bg-black/20 rounded-full mx-[1px]"></div>
<div class="w-[2px] h-3 bg-black/20 rounded-full mx-[1px]"></div>
</div>
</div>
</div>
</div>
<div class="shrink-0 w-12 h-16 rounded-xl overflow-hidden opacity-40 blur-[1px]">
<img alt="next clip" class="h-full w-full object-cover" src="https://lh3.googleusercontent.com/aida-public/AB6AXuB9Djz3R0iMJTlYR5F-CytNne1p3x18jIhCJMecVplE6tl-YKNnxp_sOeQ-oElLcriZnUU0HLKUjQy6mA7Sk7U91nC1cd3FHJm3b6__zYA9MvgaHqLTWfBed6lKEj54UxPrbDgiNhsSNPczcTo96BvINkQFOiv9E6fpdo6GhqA23Vr2nExHSFPZr9RWc9Nz36brRcvu65Tzr9Jp2GQBZaXFCj9hpV_lC2FWUPwLgL0b-Sw-lPw1R_N5DgF05-3UTwzPcgq-tlZtSdUH"/>
</div>
</div>
<div class="flex items-center justify-between mt-10 px-2">
<div class="flex flex-col items-center gap-1">
<div class="size-14 rounded-2xl bg-white dark:bg-white/5 shadow-sm border border-black/5 flex items-center justify-center text-gray-900 dark:text-white">
<span class="material-symbols-outlined text-[26px]">content_cut</span>
</div>
<span class="text-[11px] font-medium text-gray-400">Edit</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-50">
<div class="size-14 rounded-2xl bg-white dark:bg-white/5 border border-black/5 flex items-center justify-center text-gray-900 dark:text-white">
<span class="material-symbols-outlined text-[26px]">speed</span>
</div>
<span class="text-[11px] font-medium text-gray-400">Speed</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-50">
<div class="size-14 rounded-2xl bg-white dark:bg-white/5 border border-black/5 flex items-center justify-center text-gray-900 dark:text-white">
<span class="material-symbols-outlined text-[26px]">transform</span>
</div>
<span class="text-[11px] font-medium text-gray-400">Transform</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-50">
<div class="size-14 rounded-2xl bg-white dark:bg-white/5 border border-black/5 flex items-center justify-center text-gray-900 dark:text-white">
<span class="material-symbols-outlined text-[26px]">volume_up</span>
</div>
<span class="text-[11px] font-medium text-gray-400">Sound</span>
</div>
<div class="flex flex-col items-center gap-1 opacity-50">
<div class="size-14 rounded-2xl bg-white dark:bg-white/5 border border-black/5 flex items-center justify-center text-[#9333ea]">
<span class="material-symbols-outlined text-[26px] fill-1">auto_awesome</span>
</div>
<span class="text-[11px] font-medium text-gray-400">Effects</span>
</div>
</div>
</section>
<div class="h-8 w-full shrink-0"></div>
</div>

</body></html>
