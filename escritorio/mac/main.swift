// Content Scheduler para Mac: las herramientas de clipping en una ventana propia.
//
// Es una app nativa de verdad (AppKit + WKWebView), no un navegador disfrazado:
// pesa unos cientos de kilobytes y usa el motor que ya corre en este Mac.
//
// Se compila con el compilador de Swift que trae macOS. Mira construir.sh.

import AppKit
import WebKit

/// Dónde vive la página de herramientas. Se cambia desde el menú y se recuerda.
var direccion: String {
    get {
        if let v = ProcessInfo.processInfo.environment["CS_URL"], !v.isEmpty { return v }
        return UserDefaults.standard.string(forKey: "direccion") ?? "http://localhost:3200"
    }
    set { UserDefaults.standard.set(newValue, forKey: "direccion") }
}

final class Ventana: NSWindowController {
    let web: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // la clave guardada sobrevive al cierre
        web = WKWebView(frame: .zero, configuration: config)

        let ventana = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        ventana.title = "Content Scheduler"
        ventana.titlebarAppearsTransparent = true
        ventana.backgroundColor = NSColor(red: 7/255, green: 7/255, blue: 8/255, alpha: 1)
        ventana.minSize = NSSize(width: 820, height: 600)
        ventana.contentView = web
        ventana.center()
        ventana.setFrameAutosaveName("principal")

        super.init(window: ventana)
        web.navigationDelegate = self
        // Sin esto, en una app de Mac no salen ni el selector de archivos ni las
        // ventanas de confirmación, y los botones que dependen de ellos no hacen nada.
        web.uiDelegate = self
        cargar()
    }

    required init?(coder: NSCoder) { fatalError() }

    func cargar() {
        guard let u = URL(string: direccion) else { return }
        web.load(URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// Cuando el motor no está encendido no se enseña el error feo de WebKit.
    func sinMotor() {
        let html = """
        <html><head><meta charset="utf-8"><style>
          body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
               background:#070708;color:#F5F3EF;font-family:-apple-system,sans-serif;text-align:center}
          div{max-width:420px;padding:28px}
          h1{font-size:19px;margin:0 0 10px}
          p{color:#8B8890;font-size:14px;line-height:1.6;margin:0 0 20px}
          code{background:#1C1B20;padding:3px 7px;border-radius:6px;font-size:13px;color:#F5F3EF}
          button{background:#FF0A8A;color:#fff;border:0;border-radius:10px;padding:11px 22px;
                 font:inherit;font-weight:700;cursor:pointer}
        </style></head><body><div>
          <h1>El motor no está encendido</h1>
          <p>Enciéndelo en la Terminal y vuelve a intentarlo:<br><br>
             <code>cd ~/Content-Scheduler/clipper-web</code><br>
             <code>docker-compose up -d</code></p>
          <button onclick="location.href='\(direccion)'">Reintentar</button>
        </div></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: direccion))
    }
}

extension Ventana: WKNavigationDelegate {
    func webView(_ v: WKWebView, didFail _: WKNavigation!, withError _: Error) { sinMotor() }
    func webView(_ v: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { sinMotor() }

    /// Bajar un clip: se le pregunta dónde guardarlo, como cualquier app de Mac.
    func webView(_ v: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) { download.delegate = self }

    func webView(_ v: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) { download.delegate = self }

    func webView(_ v: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Un enlace a otro sitio se abre en el navegador, no dentro de la app.
        if action.navigationType == .linkActivated, let u = action.request.url,
           u.host != URL(string: direccion)?.host {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension Ventana: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing _: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        panel.begin { respuesta in
            guard respuesta == .OK, let destino = panel.url else { completionHandler(nil); return }
            try? FileManager.default.removeItem(at: destino)
            completionHandler(destino)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData _: Data?) {
        let a = NSAlert()
        a.messageText = "No se pudo guardar el archivo"
        a.informativeText = error.localizedDescription
        a.runModal()
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let u = download.progress.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([u])
    }
}

extension Ventana: WKUIDelegate {
    /// El selector de archivos, para poder elegir un video del disco.
    func webView(_ v: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame _: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    func webView(_ v: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame _: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.runModal()
        completionHandler()
    }

    /// Sin esto, un «¿seguro?» se respondía que no sin preguntar nada.
    func webView(_ v: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame _: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "Sí")
        a.addButton(withTitle: "Cancelar")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ v: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        // Lo que se abriría en pestaña nueva, al navegador.
        if let u = action.request.url { NSWorkspace.shared.open(u) }
        return nil
    }
}

final class Delegado: NSObject, NSApplicationDelegate {
    var ventana: Ventana?

    func applicationDidFinishLaunching(_: Notification) {
        menu()
        ventana = Ventana()
        ventana?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    /// El menú mínimo que macOS espera: sin esto no funcionan ni copiar ni pegar.
    private func menu() {
        let barra = NSMenu()

        let app = NSMenuItem()
        let mApp = NSMenu()
        mApp.addItem(withTitle: "Acerca de Content Scheduler", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        mApp.addItem(.separator())
        mApp.addItem(withTitle: "Recargar", action: #selector(recargar), keyEquivalent: "r")
        mApp.addItem(withTitle: "Dónde está el motor…", action: #selector(cambiarDireccion), keyEquivalent: ",")
        mApp.addItem(.separator())
        mApp.addItem(withTitle: "Agrandar", action: #selector(agrandar), keyEquivalent: "+")
        mApp.addItem(withTitle: "Achicar", action: #selector(achicar), keyEquivalent: "-")
        mApp.addItem(withTitle: "Tamaño normal", action: #selector(tamanoNormal), keyEquivalent: "0")
        mApp.addItem(.separator())
        mApp.addItem(withTitle: "Ocultar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        mApp.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = mApp
        barra.addItem(app)

        let edicion = NSMenuItem()
        let mEd = NSMenu(title: "Edición")
        mEd.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        mEd.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z")
        mEd.addItem(.separator())
        mEd.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        mEd.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        mEd.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        mEd.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edicion.submenu = mEd
        barra.addItem(edicion)

        NSApp.mainMenu = barra
    }

    @objc private func recargar() { ventana?.cargar() }

    /// Por si el motor no está en el puerto de siempre.
    @objc private func cambiarDireccion() {
        let a = NSAlert()
        a.messageText = "¿Dónde está tu motor de clipping?"
        a.informativeText = "Normalmente corre en este mismo Mac y no hay que tocar nada."
        let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        campo.stringValue = direccion
        a.accessoryView = campo
        a.addButton(withTitle: "Guardar")
        a.addButton(withTitle: "Cancelar")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let nueva = campo.stringValue.trimmingCharacters(in: .whitespaces)
        guard !nueva.isEmpty, URL(string: nueva)?.scheme != nil else { return }
        direccion = nueva
        ventana?.cargar()
    }

    @objc private func agrandar() { zoom(+0.1) }
    @objc private func achicar() { zoom(-0.1) }
    @objc private func tamanoNormal() { ventana?.web.pageZoom = 1 }

    private func zoom(_ paso: CGFloat) {
        guard let w = ventana?.web else { return }
        w.pageZoom = min(2.5, max(0.5, w.pageZoom + paso))
    }
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.setActivationPolicy(.regular)
app.run()
