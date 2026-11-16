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

// file_picker and other plugins still compile against API 34. AGP 9 rejects
// that once a dependency such as flutter_plugin_android_lifecycle was built
// with API 36. Raise the floor after each plugin's own android block.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val components = extensions.findByName("androidComponents")
            ?: error("${path}: androidComponents extension missing")
        val finalize = components.javaClass.methods.firstOrNull { method ->
            method.name == "finalizeDsl" &&
                method.parameterCount == 1 &&
                method.parameterTypes[0].name == "org.gradle.api.Action"
        } ?: error("${path}: finalizeDsl(Action) missing on ${components.javaClass.name}")
        finalize.invoke(
            components,
            org.gradle.api.Action<Any> { android -> raiseLibraryCompileSdk(path, android) },
        )
    }
}

fun raiseLibraryCompileSdk(projectPath: String, android: Any) {
    val current = android.javaClass.methods
        .firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
        ?.invoke(android) as? Int
    if (current != null && current >= 36) return
    val setter = android.javaClass.methods.firstOrNull { method ->
        method.name == "setCompileSdk" &&
            method.parameterCount == 1 &&
            (method.parameterTypes[0] == Integer::class.java ||
                method.parameterTypes[0] == Int::class.javaPrimitiveType)
    } ?: error("$projectPath: setCompileSdk(Int) missing on ${android.javaClass.name}")
    setter.invoke(android, 36)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
