allprojects {
    repositories {
        google()
        mavenCentral()
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
subprojects {
    project.evaluationDependsOn(":app")
}

// whisper_ggml still compiles against SDK 34, but its ffmpeg dependency
// requires 35+. Lift plugin libraries to our compile SDK.
subprojects {
    fun liftCompileSdk(project: Project) {
        project.extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.let { android ->
                if ((android.compileSdk ?: 0) < 36) android.compileSdk = 36
            }
    }
    if (state.executed) liftCompileSdk(this) else afterEvaluate { liftCompileSdk(this) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
