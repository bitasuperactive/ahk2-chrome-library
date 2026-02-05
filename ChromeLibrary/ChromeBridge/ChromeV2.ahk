#Requires AutoHotkey v2.0
#Include 'WebSocket.ahk'
#Include '..\..\Util\JsonParser.ahk'

/************************************************************************
 * Automatiza Google Chrome mediante el Chrome DevTools Protocol.
 * 
 * Permite administrar pestañas y ejecutar instrucciones JavaScript en 
 * Google Chrome iniciado con el parámetro `--remote-debugging-port`.
 * 
 * @description: Modify from G33kDude's Chrome.ahk v1.
 * @author thqby
 * @author bitasuperactive (documentation)
 * @date 31/01/2026
 * @version 1.0.5
 * @see https://github.com/thqby/ahk2_lib/blob/master/Chrome.ahk
 * @Warning Dependencias:
 * - WebSocket.ahk
 * - JsonParser.ahk
 ***********************************************************************/
class Chrome
{
    /**
     * @private
     * Instancia de WinHttpRequest para las solicitudes HTTP.
     */
    static _http := ComObject('WinHttp.WinHttpRequest.5.1') ;

    /**
     * @public
     * {String}
     * Nombre del ejecutable local de Chrome.
     */
    ExeName := unset

    /**
     * @public
     * {Integer}
     * Puerto de conexión para la depuración.
     */
    DebugPort := unset

    /**
     * @public
     * {Integer}
     * Identificador del proceso de Chrome.
     */
    PID := unset

    ;static Prototype.NewTab := this.Prototype.NewPage

    /**
     * @private
     * Busca la instancia ejecutada de Google Chrome para el puerto de depuración especificado.
     * @param {String} exeName Nombre del ejecutable de Chrome.
     * @param {Integer} debugPort Puerto de depuración local.
     * @returns {Object} Si encuentra una instancia, devuelve un objeto con las propiedades: 
     * `Base` - La clase Chrome, `DebugPort` - Puerto de depuración, `PID` - ID del proceso.
     * Si no encuentra ninguna instancia, devuelve `0`.
     */
    static _FindBrowserInstance(exeName, debugPort)
    {
        items := Map()
        filter_items := Map()

        wmi := ComObjGet('winmgmts:')
        processes := wmi.ExecQuery("SELECT CommandLine, ProcessID FROM Win32_Process WHERE Name = '" exeName "' AND CommandLine LIKE '% --remote-debugging-port=%'")
        for item in processes
            (!items.Has(parentPID := ProcessGetParent(item.ProcessID)) && items[item.ProcessID] := [parentPID, item.CommandLine])
        for pid, item in items
            if !items.Has(item[1]) && (!debugPort || InStr(item[2], ' --remote-debugging-port=' debugPort))
                filter_items[pid] := item[2]
        for pid, cmd in filter_items
            if RegExMatch(cmd, 'i) --remote-debugging-port=(\d+)', &m)
                return { Base: this.Prototype, DebugPort: m[1], PID: pid }
    }

    /**
     * @public
     * Inicia o conecta una instancia de Google Chrome en modo depuración y abre las URL(s) indicadas
     * si no están ya abiertas.
     * @param {String} ChromePath (Opcional) Ruta completa al ejecutable de Chrome.
     * Si se deja en blanco, se buscará en los accesos directos, registros del sistema y en la ruta estándar.
     * @param {Integer} DebugPort (Opcional) Puerto local para el modo depuración. Por defecto: `9222`.
     * @param {String} ProfilePath (Opcional) Ruta al perfil de usuario de Chrome. Si no se establece, se utilizará la ruta estándar.
     * @param {String} Flags (Opcional) Banderas adicionales para el lanzamiento de Chrome.
     * @param {String|Array<String>} URLs (Opcional) URL o colección de URL(s) a abrir al iniciar o conectar Chrome.
     * Si la url exacta ya se encuentra abierta, no se vuelve a abrir.
     */
    __New(ChromePath := "", DebugPort := 9222, ProfilePath := "", Flags := "", URLs := "")
    {
        ;// Verificar ChromePath
        if !ChromePath
            try FileGetShortcut A_StartMenuCommon '\Programs\Chrome.lnk', &ChromePath
            catch
                ChromePath := RegRead(
                    'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Chrome.exe', ,
                    'C:\Program Files (x86)\Google\Chrome\Application\Chrome.exe')
        if !FileExist(ChromePath)
            throw Error('Chrome could not be found')
        ;// Verificar DebugPort
        if !IsInteger(DebugPort) || (DebugPort <= 0)
            throw Error('DebugPort must be a positive integer')
        this.DebugPort := DebugPort
        URLString := ''

        SplitPath(ChromePath, &exename)
        this.ExeName := exename
        URLs := (URLs is Array) ? URLs : (URLs && URLs is String) ? [URLs] : []
        if instance := Chrome._FindBrowserInstance(this.Exename, DebugPort) {
            this.PID := instance.PID, http := Chrome._http
            ;// Abrir las URL(s) en la instancia existente
            for url in URLs
                if (!this.GetPageByURL(url, "exact"))
                    http.Open('PUT', 'http://127.0.0.1:' this.DebugPort '/json/new?' url), http.Send()
            return
        }

        ;// Verificar ProfilePath
        if (ProfilePath && !DirExist(ProfilePath)) {
            DirCreate(ProfilePath)
        }

        ;// Escapar las URL(s) para la línea de comandos
        for url in URLs
            URLString .= ' ' CliEscape(url)

        hasother := ProcessExist(this.Exename)
        Run(
            CliEscape(ChromePath)
            . ' --remote-debugging-port=' this.DebugPort 
            . ' --remote-allow-origins=*'
            . (ProfilePath ? ' --user-data-dir=' CliEscape(ProfilePath) : '')
            . (Flags ? ' ' Flags : '') URLString
            ,,"Max", &PID
        )
        ;// Esperar a que Chrome inicie en modo depuración
        if (hasother)
            Sleep(600)
        if (!instance := Chrome._FindBrowserInstance(this.Exename, this.DebugPort))
            throw Error(Format('{1:} is not running in debug mode. Try closing all {1:} processes and try again', this.Exename))
        this.PID := PID


        /**
         * Escapa las comillas del texto para la línea de comandos.
         */
        CliEscape(param) => '"' RegExReplace(param, '(\\*)"', '$1$1\"') '"'
    }

    /**
     * @public
     * Mata el proceso de Google Chrome asociado a esta instancia.
     */
    Kill() => ProcessClose(this.PID) ;

    /**
     * @private
     * Consulta Chrome para obtener una lista de páginas que exponen una interfaz de depuración.
     * Además de las pestañas estándar, estas incluyen páginas como la configuración de extensiones.
     * @return {Array<Map>} Colección de mapas que representan las páginas disponibles para depuración.
     */
    _GetPageList() {
        http := Chrome._http
        try {
            http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json')
            http.Send()
            return JsonParser.Parse(http.responseText)
        } catch
            return []
    }

    ; FindPages(opts, MatchMode := 'exact') {
    ;     Pages := []
    ;     for PageData in this._GetPageList() {
    ;         fg := true
    ;         for k, v in (opts is Map ? opts : opts.OwnProps())
    ;             if !((MatchMode = 'exact' && PageData[k] = v) || (MatchMode = 'contains' && InStr(PageData[k], v))
    ;             || (MatchMode = 'startswith' && InStr(PageData[k], v) == 1) || (MatchMode = 'regex' && PageData[k] ~= v
    ;             )) {
    ;                 fg := false
    ;                 break
    ;             }
    ;         if (fg)
    ;             Pages.Push(PageData)
    ;     }
    ;     return Pages
    ; }

    /**
     * @public
     * Abre una nueva página en la instancia de Chrome lista para operar.
     * @param {String} url Enlace a abrir en la nueva página. Por defecto: "about:blank".
     * @param {Func} fnCallback (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     * @returns {Chrome.Page|0} Página creada lista para operar, o `0` si no se ha podido crear.
     */
    NewPage(url := 'about:blank', fnCallback?) {
        http := Chrome._http
        http.Open('PUT', 'http://127.0.0.1:' this.DebugPort '/json/new?' url), http.Send()
        if ((PageData := JsonParser.parse(http.responseText)).Has('webSocketDebuggerUrl')){
            return Chrome.Page(StrReplace(PageData['webSocketDebuggerUrl'], 'localhost', '127.0.0.1'), fnCallback?).WaitForLoad()
        }
    }

    ; ClosePage(opts, MatchMode := 'exact') {
    ;     http := Chrome._http
    ;     switch Type(opts) {
    ;         case 'String':
    ;             return (http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json/close/' opts), http.Send())
    ;         case 'Map':
    ;             if opts.Has('id')
    ;                 return (http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json/close/' opts['id']), http.Send())
    ;         case 'Object':
    ;             if opts.HasProp('id')
    ;                 return (http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json/close/' opts.id), http.Send())
    ;     }
    ;     for page in this.FindPages(opts, MatchMode)
    ;         http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json/close/' page['id']), http.Send()
    ; }

    ; ActivatePage(opts, MatchMode := 'exact') {
    ;     http := Chrome._http
    ;     for page in this.FindPages(opts, MatchMode)
    ;         return (http.Open('GET', 'http://127.0.0.1:' this.DebugPort '/json/activate/' page['id']), http.Send())
    ; }

    /**
     * Devuelve una conexión a la interfaz de depuración de la página que coincida con los
     * criterios proporcionados lista para operar. Cuando varias páginas coinciden con los criterios, 
     * aparecen por orden de apertura más reciente.
     * @param {String} Key La clave de la lista de páginas a buscar, como "url" o "title".
     * @param {String} Value El valor a buscar en la clave proporcionada.
     * @param {String} MatchMode (Opcional) Tipo de búsqueda a realizar. Puede ser: "exact", "contains", "startswith" o "regex".
     * Por defecto: "exact".
     * @param {Integer} Index (Opcional) Si varias páginas coinciden con los criterios proporcionados, cuál de ellas devolver.
     * Por defecto: `1`.
     * @param {Func} fnCallback (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     * @returns {Chrome.Page|0} Página que coincide con los criterios o `0` si no se encuentra ninguna.
     */
    GetPageBy(Key, Value, MatchMode := 'exact', Index := 1, fnCallback?) {
        static match_fn := {
            contains: InStr,
            exact: (a, b) => a = b,
            regex: (a, b) => a ~= b,
            startswith: (a, b) => InStr(a, b) == 1
        }
        Count := 0
        try Fn := match_fn.%MatchMode%
        catch
            throw Error('Invalid MatchMode: ' . MatchMode)
        for PageData in this._GetPageList()
            if Fn(PageData[Key], Value) && ++Count == Index 
                return Chrome.Page(PageData['webSocketDebuggerUrl'], fnCallback?).WaitForLoad()
    }

    /**
     * Abreviatura de `GetPageBy('url', Value, 'startswith')`.
     * @param {String} Value Url a buscar.
     * @param {String} MatchMode (Opcional) Tipo de búsqueda a realizar. Puede ser: "exact", "contains", "startswith" o "regex".
     * Por defecto: "startswith".
     * @param {Integer} Index (Opcional) Si varias páginas coinciden con los criterios proporcionados, cuál de ellas devolver.
     * Por defecto: `1`.
     * @param {Func} fnCallback (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     * @returns {Chrome.Page|0} Página que coincide con los criterios o `0` si no se encuentra ninguna.
     */
    GetPageByURL(Value, MatchMode := 'startswith', Index := 1, fnCallback?) {
        ; Value := SubStr(Value, InStr(Value, "//") + 2) ; Eliminar protocolo
        return this.GetPageBy('url', Value, MatchMode, Index, fnCallback?)
    }

    /**
     * Abreviatura de `GetPageBy('title', Value, 'startswith')`.
     * @param {String} Value Título a buscar.
     * @param {String} MatchMode (Opcional) Tipo de búsqueda a realizar. Puede ser: "exact", "contains", "startswith" o "regex".
     * Por defecto: "startswith".
     * @param {Integer} Index (Opcional) Si varias páginas coinciden con los criterios proporcionados, cuál de ellas devolver.
     * Por defecto: `1`.
     * @param {Func} fnCallback (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     * @returns {Chrome.Page|0} Página que coincide con los criterios o `0` si no se encuentra ninguna.
     */
    GetPageByTitle(Value, MatchMode := 'startswith', Index := 1, fnCallback?) {
        return this.GetPageBy('title', Value, MatchMode, Index, fnCallback?)
    }

    /**
     * Abreviatura de `GetPageBy('type', Type, 'exact')`.
     * @param {Integer} Index (Opcional) Si varias páginas coinciden con los criterios proporcionados, cuál de ellas devolver.
     * Por defecto: `1`.
     * @param {String} Type (Opcional) Tipo de página a buscar. Por defecto es "page" que representa el área visible de una pestaña normal de Chrome.
     * @param {Func} fnCallback (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     * @returns {Chrome.Page|0} Página que coincide con los criterios o `0` si no se encuentra ninguna.
     */
    GetPage(Index := 1, Type := 'page', fnCallback?) {
        return this.GetPageBy('type', Type, 'exact', Index, fnCallback?)
    }

    /**
     * @public
     * Representa una conexión WebSocket a la interfaz de depuración de una página de Chrome.
     * @extends WebSocket
     */
    class Page extends WebSocket
    {
        /** @private */
        _index := 0 ;
        /** @private */
        _responses := Map() ;
        /** @private */
        _callback := 0 ;

        /**
         * @public
         * {Boolean}
         * Estado de la conexión con la página.
         */
        KeepAlive := 0 ;

        /**
         * @public
         * Conecta con la interfaz de depuración de una página web determinada por su WebSocket URL.
         * - Mantiene viva la conexión enviando una solicitud cada 25 segundos.
         * - Se autodesecha al cerrar la pestaña.
         * @param {String} url URL WebSocket de la página a conectar.
         * @param {Func} events (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
         */
        __New(url, events := 0) {
            super.__New(url)
            this._callback := events
            pthis := ObjPtr(this)
            SetTimer(this.KeepAlive := () => ObjFromPtrAddRef(pthis)('Browser.getVersion', , false), 25000)
        }
        
        /**
         * @public
         * Destruye correctamente la instancia de la clase.
         */
        __Delete() {
            if !this.KeepAlive
                return
            SetTimer(this.KeepAlive, 0), this.KeepAlive := 0
            super.__Delete()
        }

        /**
         * @public
         * Llamada web.
         * @param DomainAndMethod Dominio y método WebSocket, por ejemplo: `Runtime.Evaluate`.
         * @param Params (Opcional) Parámetros para la llamada.
         * @param {Boolean} WaitForResponse (Opcional) Si esperar por la respuesta. Por defecto: `true`.
         * @returns {Any} Resultado de la operación.
         */
        Call(DomainAndMethod, Params?, WaitForResponse := true) {
            if (this.readyState != 1)
                throw Error('Not connected to tab')

            ; Use a temporary variable for ID in case more calls are made
            ; before we receive a response.
            if !ID := this._index += 1
                ID := this._index += 1
            this.sendText(JsonParser.stringify(Map('id', ID, 'params', Params ?? {}, 'method', DomainAndMethod), 0))
            if (!WaitForResponse)
                return

            ; Wait for the response
            this._responses[ID] := false
            while (this.readyState = 1 && !this._responses[ID])
                Sleep(20)

            ; Get the response, check if it's an error
            if !response := this._responses.Delete(ID)
                throw Error('Not connected to tab')
            if !(response is Map)
                return response
            if (response.Has('error'))
                throw Error('Chrome indicated error in response', , JsonParser.Stringify(response['error']))
            try return response['result']
        }
        
        /**
         * @public
         * Ejecuta instrucciones JavaScript.
         * @param {String} JS Cadena de instrucciones JavaScript.
         * @returns {Object|0} Objeto de respuesta web con las propiedades: 
         * `className`, `description`, `objectId`, `subtype`, `type`, `value`.
         * @throws {Error} Si el código JavaScript ha generado una excepción.
         */
        Evaluate(JS)
        {
            params := {
                expression: JS,
                objectGroup: 'console',
                includeCommandLineAPI: JsonParser.true,
                silent: JsonParser.false,
                returnByValue: JsonParser.false,
                userGesture: JsonParser.true,
                awaitPromise: JsonParser.false
            }
            response := this('Runtime.evaluate', params)
            if (response is Map) {
                if (response.Has('exceptionDetails'))
                    throw Error(response['result']['description'], , JsonParser.stringify(response['exceptionDetails']))
                return response['result']
            }
        }
        
        /**
         * @public
         * Ejecuta instrucciones JavaScript y espera a que cargue el documento.
         * @param {String} JS Cadena de instrucciones JavaScript.
         * @returns {Object|0} Objeto de respuesta web con las propiedades: 
         * `className`, `description`, `objectId`, `subtype`, `type`, `value`.
         * @throws {Error} Si el código JavaScript ha generado una excepción.
         */
        WaitForEvaluate(JS)
        {
            this.WaitForLoad()
            this.Evaluate(JS)
            this.WaitForLoad()
        }

        /**
         * @public
         * Cierra la página web.
         */
        Close() {
            RegExMatch(this.url, 'ws://[\d\.]+:(\d+)/devtools/page/(.+)$', &m)
            http := Chrome._http, http.Open('GET', 'http://127.0.0.1:' m[1] '/json/close/' m[2]), http.Send()
            this.__Delete()
        }

        /**
         * @public
         * Activa la página web y espera a que el documento finalice de cargar.
         */
        Activate() {
            http := Chrome._http, RegExMatch(this.url, 'ws://[\d\.]+:(\d+)/devtools/page/(.+)$', &m)
            http.Open('GET', 'http://127.0.0.1:' m[1] '/json/activate/' m[2]), http.Send()
            return this.WaitForLoad()
        }

        /**
         * Espera a que el documento pase al estado indicado.
         * @note El documento pasa al estado "complete" sin finalizar la carga
         * los elementos asíncronos. Si se requieren, utilizar `WaitForElement`.
         * @param {String} DesiredState (Opcional) Estado deseado para el documento.
         * Por defecto: "complete".
         * @param {Integer} Interval Intervalo en milisegundos de espera entre las evaluaciones 
         * del estado.
         * @returns {Chrome.Page}
         * @see https://www.w3schools.com/jsref/prop_doc_readystate.asp
         */
        WaitForLoad(DesiredState := 'complete', Interval := 100) {
            while (state := this.Evaluate('document.readyState')['value']) != DesiredState
                Sleep Interval
            return this
        }

        /**
         * Espera a que aparezca un elemento en el documento.
         * @note Alternativa a `WaitForLoad` más robusta.
         * @param {String} selector CSS selector.
         * @param {Integer} limit (Opcional) Límite de tiempo (ms) para anular la búsqueda del elemento.
         * Por defecto: `8000`.
         * @returns {Boolean} Verdadero si se encuentra el elemento. Falso en su defecto.
         * @see https://www.w3schools.com/cssref/css_selectors.php
         */
        WaitForElement(selector, limit := 8000)
        {
            this.WaitForLoad()
            interval := 100 ; ms
            iterations := (limit / interval)
            Loop iterations {
                if (__ElementExistInDOM(selector))
                    return true
                Sleep(interval)
            }
            return false
            

            __ElementExistInDOM(selector) => this.Evaluate("document.querySelector('" selector "')").Has("objectId")
        }

        /**
         * @public
         * Intenta reconectar la página ante un cierre inesperado. Si falla, elimina la página.
         */
        onClose(*) {
            try this.reconnect()
            catch WebSocket.Error
                this.__Delete()
        }
        
        /**
         * @public
         * Almacena el mensaje recibido de la página web e intenta ejecutar el callback establecido.
         * @param {String} msg Mensaje de la página.
         */
        onMessage(msg) {
            data := JsonParser.parse(msg)
            if this._responses.Has(id := data.Get('id', 0))
                this._responses[id] := data
            if (data.Get("method", "") = "Inspector.detached")
                 (this.onClose)(this)
            try (this._callback)(data)
        }
    } ;
}