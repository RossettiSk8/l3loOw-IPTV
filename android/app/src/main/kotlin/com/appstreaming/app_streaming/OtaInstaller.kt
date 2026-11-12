package com.appstreaming.app_streaming

import android.content.Intent
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class OtaFileProvider : FileProvider()

internal class OtaInstaller(private val activity: MainActivity) {
    private val staging by lazy { File(activity.cacheDir, "ota") }
    private val packageManager get() = activity.packageManager
    private val packageName get() = activity.packageName

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "installedVersion" -> {
                    val installed = installed()
                    result.success(mapOf(
                        "version" to (installed.versionName ?: ""),
                        "build" to versionCode(installed),
                    ))
                }
                "authorize" -> result.success(authorize())
                "createPackageFile" -> {
                    check(staging.isDirectory || staging.mkdirs())
                    val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
                    staging.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
                    result.success(File.createTempFile("update-", ".apk", staging).absolutePath)
                }
                "install" -> {
                    val path = requireNotNull(call.argument<String>("path"))
                    val build = requireNotNull(call.argument<Number>("build")).toLong()
                    install(path, build)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("ota_failed", "Android no pudo preparar la instalación.", null)
        }
    }

    private fun canInstall() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun authorize(): Boolean {
        if (canInstall()) return true
        activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
        )
        return false
    }

    @Suppress("DEPRECATION")
    private fun installed(): PackageInfo = packageManager.getPackageInfo(packageName, 0)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun install(path: String, build: Long) {
        check(canInstall())
        val file = File(path).canonicalFile
        require(file.parentFile == staging.canonicalFile && file.extension == "apk" && file.isFile)
        val archive = requireNotNull(packageManager.getPackageArchiveInfo(file.path, 0))
        require(archive.packageName == packageName)
        require(versionCode(archive) == build && build > versionCode(installed()))

        val uri = FileProvider.getUriForFile(activity, "$packageName.ota", file)
        activity.startActivity(
            Intent(Intent.ACTION_INSTALL_PACKAGE)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
    }
}
