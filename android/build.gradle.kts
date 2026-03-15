buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.google.gms:google-services:4.3.15")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// AGP 8+ 호환: namespace 누락된 외부 Flutter plugin(android library) 자동 보정
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android") ?: return@withId
        try {
            val getNamespace = androidExt.javaClass.getMethod("getNamespace")
            val currentNamespace = getNamespace.invoke(androidExt) as String?
            if (currentNamespace.isNullOrBlank()) {
                val fallbackNamespace = "dev.flutter.${project.name.replace('-', '_')}"
                val setNamespace =
                    androidExt.javaClass.getMethod("setNamespace", String::class.java)
                setNamespace.invoke(androidExt, fallbackNamespace)
                println(
                    "[Gradle][NamespaceFallback] ${project.path} -> $fallbackNamespace",
                )
            }
        } catch (e: Exception) {
            println(
                "[Gradle][NamespaceFallback] ${project.path} namespace 보정 실패: ${e.message}",
            )
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
