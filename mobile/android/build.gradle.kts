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

// tflite_flutter declares Java 11 in its own build.gradle but leaves Kotlin to
// default to the JDK the build runs on - JDK 21 here - and AGP 9 rejects the
// mismatch outright:
//
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileReleaseJavaWithJavac' (11) and 'compileReleaseKotlin' (21)
//
// So Kotlin is pinned to 11 to match the Java target the plugin chose for
// itself. The reverse - dragging both up to 17 - does not work from here: AGP
// derives the Java task's target from the plugin's own
// `android { compileOptions { ... } }`, and reconfiguring another project's
// android extension late enough to win means an afterEvaluate that throws on
// `:app`, which the evaluationDependsOn above has already evaluated.
//
// Scoped to this one subproject deliberately. Every other plugin here is
// already internally consistent, and forcing a target across all of them would
// break any that compile at a different one. Editing the plugin inside the pub
// cache would not survive the next `pub get`, and relaxing
// kotlin.jvm.target.validation.mode to `warning` would only silence the report
// while still mixing class file versions inside one library.
subprojects {
    if (name == "tflite_flutter") {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
            .configureEach {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
                )
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
