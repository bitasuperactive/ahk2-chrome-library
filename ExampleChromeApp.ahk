#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "ChromeLibrary\JSWrapper.ahk"
#Include "Util\OrObject.ahk"

ExampleChromeApp().Run()

/**
 * @internal
 * Aplicación de ejemplo que integra automatización de Excel y Chrome.
 * 
 * Arquitectura modular:
 * - ExampleApp      -> Orquestador de alto nivel (eventos UI <-> servicios)
 * - ExampleWindow   -> Interfaz gráfica (presentación pura, sin lógica)
 * - ChromeService   -> Envuelve ChromeV2 + JSWrapper y cachea páginas
 * 
 * @author 1Vita, DeepSeek (structure)
 */
class ExampleChromeApp
{
    /** @type {ExampleWindow} */
    Window := unset
    /** @type {ChromeService} */
    Chrome := unset

    /**
     * Usa `Run()` para iniciar.
     */
    __New() {
        this.Window := ExampleWindow()
        this.Chrome := ChromeService(this.Window)
        this._WireEvents()
    }

    /**
     * Muestra la interfaz.
     */
    Run() => this.Window.Show()

    ; --- Composición de eventos entre UI y servicios -----------------------
    _WireEvents() {
        w := this.Window

        ; Chrome
        w.OnChromeConnect    := (*)    => this.Chrome.Connect()
        w.OnChromeDisconnect := (*)    => this.Chrome.Disconnect()
        w.OnExtractTable     := (*)    => this._PreviewWebTable()
        w.OnLoginDemo        := (*)    => this._LoginDemo()
    }

    ; --- Handlers Chrome ---------------------------------------------------
    _PreviewWebTable() {
        page := this.Chrome.GetOrCreatePage(ChromeService.DEMO_TABLE_URL)
        if (!page)
            return

        rows := page.RetrieveTableData(ChromeService.DEMO_TABLE_SELECTOR)
        if (!rows.Length) {
            MsgBox("La página no contiene tablas accesibles.", "Aviso", 48)
            return
        }

        preview := "Se han extraído " rows.Length " filas.`n`n"
        for i, row in rows {
            if (i > 5) {
                preview .= "..."
                break
            }
            preview .= "[" i "] "
            for k, v in row.OwnProps()
                preview .= k "=" v "`n"
            preview .= "`n"
        }
        MsgBox(preview, "Vista previa de la tabla web")
    }

    _LoginDemo() {
        page := this.Chrome.GetOrCreatePage(ChromeService.LOGIN_URL)
        if (!page)
            return

        ok := page.Login(
            "#username", "#password",
            "button[type='submit']", "#flash.error",
            "tomsmith", "SuperSecretPassword!"
        )
        MsgBox(
            ok ? "Login exitoso." : "Error de autenticación.",
            ok ? "Éxito" : "Error",
            ok ? 64 : 16
        )
    }
}


; ============================================================================
; ExampleWindow - Interfaz de usuario (solo presentación)
; ============================================================================
class ExampleWindow
{
    ; --- Eventos expuestos a ExampleApp -----------------------------------
    OnChromeConnect    := (*) => 0
    OnChromeDisconnect := (*) => 0
    OnExtractTable     := (*) => 0
    OnLoginDemo        := (*) => 0

    ; --- Estado interno ----------------------------------------------------
    /** @type {ExampleWindow} */
    _form    := unset
    /** @type {Map<String, Gui.Control>} */
    _ctrl    := Map()

    __New() {
        this._BuildUI()
        this._WireInternalEvents()
    }

    Show() => this._form.Show()

    SetChromeConnected(connected) {
        this._ctrl["ChromeConnectBtn"].Enabled    := !connected
        this._ctrl["ChromeDisconnectBtn"].Enabled := connected
        this._ctrl["ChromeGroup"].Text := connected ? "CHROME ✅" : "CHROME"
        this._ctrl["ExtractTableBtn"].Enabled := connected
        this._ctrl["LoginDemoBtn"].Enabled    := connected
        SetTimer((*) => WinActivate(this._form.Hwnd), -600)
    }

    ; --- Construcción de la UI ---------------------------------------------
    _BuildUI() {
        form := Gui("+Border +Caption -Resize", "ExampleGUI - Chrome")
        form.SetFont("s10", "Segoe UI")
        this._form := form

        c := this._ctrl

        ; ---------------------------------------------------------------
        ; Botones de Chrome
        ; ---------------------------------------------------------------
        c["ChromeConnectBtn"]    := form.AddButton("x15  y10 w160 h32",           "Conectar Chrome")
        c["ChromeDisconnectBtn"] := form.AddButton("x185 y10 w160 h32 Disabled",  "Desconectar Chrome")

        ; ---------------------------------------------------------------
        ; Grupo CHROME
        ; ---------------------------------------------------------------
        c["ChromeGroup"]     := form.AddGroupBox("x15 y55 w670 h70", "CHROME")
        c["ExtractTableBtn"] := form.AddButton("x30  y85 w200 h28 Disabled", "Extraer tabla web")
        c["LoginDemoBtn"]    := form.AddButton("x245 y85 w200 h28 Disabled", "Probar login")
    }

    _WireInternalEvents() {
        this._form.OnEvent("Close", (*) => ExitApp())

        c := this._ctrl

        c["ChromeConnectBtn"].OnEvent(  "Click",    (*) => this.OnChromeConnect())
        c["ChromeDisconnectBtn"].OnEvent("Click",   (*) => this.OnChromeDisconnect())
        c["ExtractTableBtn"].OnEvent(   "Click",    (*) => this.OnExtractTable())
        c["LoginDemoBtn"].OnEvent(      "Click",    (*) => this.OnLoginDemo())
    }
}

; ============================================================================
; ChromeService - Encapsula ChromeV2 + JSWrapper
; ============================================================================
class ChromeService
{
    static PROFILE            => "C:\Temp\ChromeDebug"
    static DEMO_TABLE_URL     => "https://the-internet.herokuapp.com/tables"
    static DEMO_TABLE_SELECTOR=> "#table1"
    static LOGIN_URL          => "https://the-internet.herokuapp.com/login"

    /** @type {ExampleWindow} */
    _window  := unset
    /** @type {ChromeV2} */
    _manager := unset
    /** @type {Map<String, JSWrapper>} */
    _pages := Map()
    /** @type {ProcessWMIWatcher} */
    _wmiHandler := unset

    __New(window) => this._window := window

    IsConnected() => this.HasOwnProp("_manager") && this._manager != 0

    Connect() {
        if (this.IsConnected())
            return
        try {
            this._manager := ChromeV2(,, ChromeService.PROFILE)
        } catch Error as err {
            MsgBox("No se ha podido iniciar Chrome:`n`n" err.Message, "Error", 16)
            return
        }
        this._wmiHandler := this._manager.OnClose((*) => this._OnChromeCloseHandler())
        this._window.SetChromeConnected(true)
    }

    Disconnect() {
        if (!this.IsConnected())
            return
        this._pages.Clear()
        this._wmiHandler.Dispose()
        this._manager.Kill()
        this._manager := unset
        this._window.SetChromeConnected(false)
    }

    GetOrCreatePage(url) {
        if (!this.IsConnected())
            return 0

        if (this._pages.Has(url)) {
            try {
                this._pages[url].Evaluate("1+1") ; ping de vida
                this._pages[url].Activate()
                ;// Al cachear los JSWrapper, tenemos que verificar que estamos en la url correcta.
                this._pages[url].ResetNavigation()
                return this._pages[url]
            }
             catch Error as err {
                this._pages.Delete(url)
            }
        }

        try {
            page := JSWrapper(this._manager, url)
            this._pages[url] := page
            return page
        } catch Error as err {
            MsgBox("No se ha podido abrir la página:`n`n" err.Message, "Error", 16)
            return 0
        }
    }

    _CloseBlankPages() {
        try {
            blanks := this._manager.FindPages({url: "chrome://newtab/"}, "exact")
            for blank in blanks
                try this._manager.ClosePage(blank, "exact")
        }
    }

    _OnChromeCloseHandler() {
        this.Disconnect()
        MsgBox("Chrome se ha cerrado inesperadamente.", "Aviso", 48)
    }
}