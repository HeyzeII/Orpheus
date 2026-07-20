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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val configureNamespace = {
        if (name == "isar_flutter_libs") {
            extensions.findByName("android")?.let {
                configure<com.android.build.api.dsl.LibraryExtension> {
                    namespace = "dev.isar.isar_flutter_libs"
                }
            }
        }

        // Force compileSdk to 34 for all subprojects to resolve lStar attribute conflicts
        extensions.findByName("android")?.let { android ->
            var success = false
            for (method in android.javaClass.methods) {
                if (method.name == "setCompileSdk" && method.parameterCount == 1) {
                    val paramType = method.parameterTypes[0]
                    if (paramType == Int::class.java || paramType == java.lang.Integer::class.java) {
                        try {
                            method.invoke(android, 34)
                            success = true
                        } catch (e: Exception) {}
                        break
                    }
                }
            }
            if (!success) {
                for (method in android.javaClass.methods) {
                    if (method.name == "setCompileSdkVersion" && method.parameterCount == 1) {
                        val paramType = method.parameterTypes[0]
                        if (paramType == Int::class.java || paramType == java.lang.Integer::class.java) {
                            try {
                                method.invoke(android, 34)
                            } catch (e: Exception) {}
                            break
                        }
                    }
                }
            }
        }
    }
    if (state.executed) {
        configureNamespace()
    } else {
        afterEvaluate {
            configureNamespace()
        }
    }
}