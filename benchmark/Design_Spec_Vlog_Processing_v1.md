<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>Vlog Generation Progress - 3s App</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&amp;display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/icon?family=Material+Icons+Round" rel="stylesheet"/>
<script src="https://cdn.tailwindcss.com?plugins=forms,typography"></script>
<script>
        tailwind.config = {
            darkMode: "class",
            theme: {
                extend: {
                    colors: {
                        primary: "#3B82F6", // Blue from the original spinner/description
                        "secondary-accent": "#FB923C", // Orange for the gradient mentioned
                        "background-light": "#F8F9FA",
                        "background-dark": "#121212",
                        "surface-light": "#FFFFFF",
                        "surface-dark": "#1E1E1E",
                    },
                    fontFamily: {
                        display: ["Inter", "sans-serif"],
                    },
                    borderRadius: {
                        DEFAULT: "1rem",
                        "xl": "1.5rem",
                        "2xl": "2rem",
                    },
                    animation: {
                        'float': 'float 6s ease-in-out infinite',
                        'fly-in-1': 'flyIn1 2s ease-in-out infinite',
                        'fly-in-2': 'flyIn2 2s ease-in-out 0.4s infinite',
                        'fly-in-3': 'flyIn3 2s ease-in-out 0.8s infinite',
                        'pulse-glow': 'pulseGlow 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
                    },
                    keyframes: {
                        float: {
                            '0%, 100%': { transform: 'translateY(0)' },
                            '50%': { transform: 'translateY(-20px)' },
                        },
                        flyIn1: {
                            '0%': { transform: 'translate(-120%, -120%) scale(0.8)', opacity: '0' },
                            '40%': { opacity: '1' },
                            '100%': { transform: 'translate(0, 0) scale(0.2)', opacity: '0' }
                        },
                        flyIn2: {
                            '0%': { transform: 'translate(120%, -50%) scale(0.8)', opacity: '0' },
                            '40%': { opacity: '1' },
                            '100%': { transform: 'translate(0, 0) scale(0.2)', opacity: '0' }
                        },
                        flyIn3: {
                            '0%': { transform: 'translate(-50%, 120%) scale(0.8)', opacity: '0' },
                            '40%': { opacity: '1' },
                            '100%': { transform: 'translate(0, 0) scale(0.2)', opacity: '0' }
                        },
                        pulseGlow: {
                            '0%, 100%': { boxShadow: '0 0 15px 0px rgba(59, 130, 246, 0.5)' },
                            '50%': { boxShadow: '0 0 25px 5px rgba(59, 130, 246, 0.8)' },
                        }
                    }
                },
            },
        };
    </script>
<style>.bokeh-bg {
            background: 
                radial-gradient(circle at 15% 50%, rgba(59, 130, 246, 0.15) 0%, transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(251, 146, 60, 0.15) 0%, transparent 25%),
                radial-gradient(circle at 50% 80%, rgba(59, 130, 246, 0.1) 0%, transparent 30%);
            filter: blur(40px);
            z-index: 0;
        }.grid-bg {
            background-image: 
                linear-gradient(rgba(0,0,0,0.03) 1px, transparent 1px),
                linear-gradient(90deg, rgba(0,0,0,0.03) 1px, transparent 1px);
            background-size: 100px 100px;
        }
        .dark .grid-bg {
            background-image: 
                linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
                linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
        }
    </style>
<style>
    body {
      min-height: max(884px, 100dvh);
    }
  </style>
  </head>
<body class="bg-background-light dark:bg-background-dark font-display text-gray-900 dark:text-white h-screen overflow-hidden flex flex-col items-center justify-center relative transition-colors duration-300">
<div class="absolute inset-0 bokeh-bg animate-pulse"></div>
<div class="absolute inset-0 grid-bg opacity-50 z-0"></div>
<div class="absolute top-10 left-10 w-32 h-32 bg-gray-200 dark:bg-gray-800 rounded-lg blur-md opacity-40 z-0 transform rotate-12"></div>
<div class="absolute top-40 right-10 w-40 h-56 bg-gray-300 dark:bg-gray-700 rounded-lg blur-md opacity-30 z-0 transform -rotate-6"></div>
<div class="absolute bottom-20 left-20 w-48 h-32 bg-gray-200 dark:bg-gray-800 rounded-lg blur-md opacity-40 z-0 transform rotate-3"></div>
<div class="absolute bottom-40 right-20 w-24 h-24 bg-gray-300 dark:bg-gray-700 rounded-lg blur-md opacity-30 z-0 transform -rotate-12"></div>
<main class="relative z-10 w-full max-w-md px-8 flex flex-col items-center">
<div class="relative w-48 h-48 flex items-center justify-center mb-12">
<div class="relative w-20 h-20 bg-gradient-to-br from-primary to-blue-600 rounded-full flex items-center justify-center shadow-lg animate-pulse-glow z-20">
<span class="material-icons-round text-white text-5xl ml-1">play_arrow</span>
</div>
<div class="absolute w-14 h-14 bg-cover bg-center rounded-lg shadow-md animate-fly-in-1 border-2 border-white dark:border-gray-700 overflow-hidden z-10" style="background-image: url('https://lh3.googleusercontent.com/aida-public/AB6AXuA2itI3XsBp8G3DGX3XOPyWyQZV4Hr-CfKLEmJHW42J3e2XNcQmkjPLu95Hdpk1Yggg83nZqi_EJYCWNMIi5z5BxvDP6tiRHFIgPT50NdZaZ_epr8rvJ8IFtu6MRb1Ups6cL-7npwpze38QDS-WEA2Dk4ocdiy1hHJCRjcseZsbgFsFHX2EmrOIB17gq5W8v4G5Hw-9m3u-_CgnsvBMKSb4TBB3PDxHJlt8Au790UuzAC0h2Tk7Bd1pxhhnhbvBHw_RfeUfG6DMgJLz');"></div>
<div class="absolute w-14 h-14 bg-cover bg-center rounded-lg shadow-md animate-fly-in-2 border-2 border-white dark:border-gray-700 overflow-hidden z-10" style="background-image: url('https://lh3.googleusercontent.com/aida-public/AB6AXuAMpiD_LF_Ov4GWpav1LS9oJBsnmSphWiEnqwW_BJD1DJGjTWIAgWZTtWkDDeIvy4cKTQaTFf6TAJShTYS4QQ4-yKMXI61nTe58whpM6gSS22hU0o-hE0BJdt2rQFSvlVlzEvDFaUW6ETN70OY-6KiAT4pgBNPBYehZlCMwPJdvaqLei9p0cp_B5TZKMaiz3jRCHy7rnhENIfDbnPzyKXV65Cz0gR6hM1q1IOhD4MQUwv1L2_gqun8B7ogNscwpzCYzfsJIeckZQF0j');"></div>
<div class="absolute w-14 h-14 bg-cover bg-center rounded-lg shadow-md animate-fly-in-3 border-2 border-white dark:border-gray-700 overflow-hidden z-10" style="background-image: url('https://lh3.googleusercontent.com/aida-public/AB6AXuDivv1FveBzQYmRlzAnWCUbUxMgLWRKP4i3TXSrlhsVnpIEaeBVHRMj89h_64y9RrOG7X-NIDNCw2x5K0dz-pDUxVm-uh1nd1a4QaT7QAJ1QVMdHuLj473kcvdWHhrdvlTzKcsGtMyaI93WkSiG-SJIqpj5kJzKACywfMaAHrWZzBO37-wQKJcIfsbvdO-bVKqHimuZScTw_RQ__-pgu0of9v9fZ7yMs8I7JBlor1monXUNqK0UXP_6eRbQMr47BggjiCffcRrA4MIa');"></div>
<div class="absolute inset-0 border border-primary/20 rounded-full w-40 h-40 m-auto animate-spin" style="animation-duration: 10s;"></div>
<div class="absolute inset-0 border border-dashed border-secondary-accent/30 rounded-full w-32 h-32 m-auto animate-spin" style="animation-duration: 15s; animation-direction: reverse;"></div>
</div>
<div class="text-center mb-8 space-y-2">
<h1 class="text-2xl font-bold tracking-tight text-gray-800 dark:text-gray-100">
                Creating your 3s magic...
            </h1>
<p class="text-3xl font-light text-primary animate-pulse">
                50%
            </p>
</div>
<div class="w-full h-3 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden shadow-inner">
<div class="h-full w-1/2 bg-gradient-to-r from-primary to-secondary-accent rounded-full relative">
<div class="absolute top-0 left-0 bottom-0 right-0 bg-gradient-to-r from-transparent via-white/30 to-transparent w-full -translate-x-full animate-[shimmer_2s_infinite]"></div>
</div>
</div>
<p class="mt-4 text-sm text-gray-500 dark:text-gray-400 font-medium">
            Merging clips &amp; applying filters
        </p>
</main>
<div class="absolute bottom-10 z-20">
<button class="px-6 py-2 rounded-full border border-gray-300 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors text-sm font-medium">
            Cancel
        </button>
</div>

</body></html>
