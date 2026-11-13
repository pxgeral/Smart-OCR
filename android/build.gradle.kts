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
// Plugin onnxruntime (terjemahan offline) mengunci compileSdk 33, padahal
// dependensi AndroidX di aplikasi ini butuh minimal 34. Hanya compileSdk-nya
// yang dinaikkan; minSdk/targetSdk tidak berubah. Harus sebelum evaluationDependsOn.
subprojects {
    if (project.name == "onnxruntime") {
        afterEvaluate {
            extensions
                .findByType(com.android.build.api.dsl.LibraryExtension::class.java)
                ?.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
