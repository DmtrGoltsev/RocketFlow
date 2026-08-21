package com.rocketflow.companion

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class MainActivityManifestUnitTest {
    @Test
    fun mainActivityUsesSingleTaskForWarmDeepLinks() {
        val activity = mainActivityNode()

        assertEquals(
            "singleTask",
            activity.attributes.getNamedItemNS(ANDROID_NAMESPACE, "launchMode")?.nodeValue
        )
    }

    @Test
    fun mainActivityResizesFormsAboveTheIme() {
        val activity = mainActivityNode()

        assertEquals(
            "adjustResize",
            activity.attributes.getNamedItemNS(ANDROID_NAMESPACE, "windowSoftInputMode")?.nodeValue
        )
    }

    private fun mainActivityNode(): org.w3c.dom.Node {
        val manifest = sequenceOf(
            File("src/main/AndroidManifest.xml"),
            File("app/src/main/AndroidManifest.xml")
        ).first { it.isFile }
        val document = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
        }.newDocumentBuilder().parse(manifest)
        return document.getElementsByTagName("activity")
            .let { nodes -> (0 until nodes.length).map { nodes.item(it) } }
            .first { node ->
                node.attributes.getNamedItemNS(ANDROID_NAMESPACE, "name")?.nodeValue == ".MainActivity"
            }
    }

    private companion object {
        const val ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
    }
}
