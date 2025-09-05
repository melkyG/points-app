// android/build.gradle.kts

import org.gradle.api.tasks.Delete

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // Firebase plugin
        classpath("com.google.gms:google-services:4.4.2")
    }
}

// Redirect build outputs (optional)
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
