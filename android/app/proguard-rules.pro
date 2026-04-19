# Project-specific Proguard/R8 rules.
# Start minimal and expand only when specific classes are stripped incorrectly.

# Keep line number/source info for better crash readability with mapping.
-keepattributes SourceFile,LineNumberTable

# Flutter plugins usually work without extra rules; add plugin-specific keep rules only if needed.

