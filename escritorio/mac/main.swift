// Content Scheduler para Mac: las herramientas de clipping en una ventana propia.
//
// Es una app nativa de verdad (AppKit + WKWebView), no un navegador disfrazado:
// pesa unos cientos de kilobytes y usa el motor que ya corre en este Mac.
//
// Se compila con el compilador de Swift que trae macOS. Mira construir.sh.

import AppKit
import WebKit

/// Dónde vive la página de herramientas. Se puede cambiar con CS_URL.
let direccion = ProcessInfo.processInfo.environment["CS_URL"] ?? "http://localhost:3200"

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
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.setActivationPolicy(.regular)
app.run()
