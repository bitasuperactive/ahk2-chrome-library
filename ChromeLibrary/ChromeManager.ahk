#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "ChromeBridge\ChromeV2.ahk"
#Include "..\Util\EventController.ahk"
#Include "..\Util\Utils.ahk"

/**
 * En la primera ejecución se debe configurar un nuevo perfil de usuario para Chrome Debug mode, que se almacenará en "C:\Temp\ChromeDebug".
 * Para ello se debe lanzar el siguiente comando desde cmd y completar el interrogatorio de Google:
        taskkill /F /IM chrome.exe && start chrome.exe --remote-debugging-port=9222 --user-data-dir="C:\Temp\ChromeDebug" --new-window
 * 
 * Websites for testing automation:
 *      https://the-internet.herokuapp.com/
 *      https://www.saucedemo.com/
 */

/**
 * Controlador para Google Chrome Debug Mode.
 * @requires Chrome.ahk
 * @requires EventController.ahk
 */
class ChromeManager
{
    /**
     * Enumerador para los eventos disponibles.
     */
    class EventEnum
    {
        /**
         * Se produce cuando esta instancia de Chrome.exe es cerrada.
         */
        static CLOSE := "Close"
    }

    _chrome := unset
    Controller := unset

    __New(url := "")
    {
        mainDrive := SubStr(A_ComSpec, 1, 2) ;// 'C:'
        this._chrome := Chrome(
            ChromePath:="",
            DebugPort:=9222,
            ProfilePath:=mainDrive "\Temp\ChromeDebug",
            Flags:="",
            URLs:=url,
        )
        this.Controller := EventController()
        SetTimer((*) => this.ProcessMonitor(), 1000)
        OnExit((*) => this.exitHandler())
    }

    ProcessMonitor()
    {
        if (!ProcessExist(this._chrome.PID)) {
            SetTimer((*) => this.ProcessMonitor(), 0)
            this.Controller.Trigger(ChromeManager.EventEnum.CLOSE)
        }
    }

    Kill() => this._chrome.Kill()

    /**
     * Abre el enlace especificado en una nueva página.
     * @param {String} url Enlace a navegar.
     * @returns {Chrome.Page} Página resultante.
     */
    NewPage(url := 'about:blank') => this._chrome.NewPage(url)

    /**
     * Abre el enlace solicitado si no está ya abierto.
     * * Espera a que el DOM finalice de cargar.
     * @param {String} url Enlace completo a la web objetivo.
     * @returns {Chrome.Page} Página solicitada con el DOM listo para operar.
     */
    GetPage(url)
    {
        page := this.IsPageOpened(url)
        if (!IsObject(page))
            page := this.NewPage(url)
        if (!IsObject(page))
            throw Error("No ha sido posible obtener la página web solicitada.")

        return page.WaitForLoad()
    }

    /**
     * Comprueba si la página solicitada está abierta.
     * @param {String} url Enlace parcial de la página objetivo.
     * @returns {Chrome.Page} Página solicitada, 0 en su defecto.
     */
    IsPageOpened(url)
    {
        ;// Eliminar protocolo para la búsqueda
        url := SubStr(url, InStr(url, "//") + 2)
        return this._chrome.GetPageByURL(url, "contains")
    }


    ;---------------------------------
    ; FUNCIONES JAVASCRIPT
    ;---------------------------------

    /**
     * Transforma una tabla de la web objetivo en una colección de objetos literales 
     * con sus datos.
     * @param {Chrome.Page} page Página web objetivo.
     * @param {String} query Consulta para la selección de la tabla objetivo.
     * @returns {Array} Colección de pares cabecera-dato.
     */
    GetTableEntries(page, query) ;// [Object]
    {
        ;page := this.GetPage("https://webdriveruniversity.com/Data-Table/index.html")
        page.WaitForElement(query)
        rowSeparator := "`n"
        dataSeparator := ";"
        objArray := []
        
        ;// Recuperar cabeceras y datos
        headersEvaluation := page.Evaluate(js(query, "th"))
        dataEvaluation := page.Evaluate(js(query, 'td, th[scope="row"]'))

        ;// Dividir las respuestas en colecciones de cadenas
        headerRows := (headersEvaluation.Has("value")) ? StrSplit(headersEvaluation["value"], rowSeparator) : []
        dataRows := (dataEvaluation.Has("value")) ? StrSplit(dataEvaluation["value"], rowSeparator) : []

        if (!headerRows.Has(1) && !dataRows.Has(1)) {
            return []
        }

        ;// Si no hay cabeceras, crearlas
        headers := []
        if (headerRows.Has(1)) {
            headers := StrSplit(headerRows[1], dataSeparator)
        } else {
            rowLength := StrSplit(dataRows[1], dataSeparator).Length
            Loop rowLength
                headers.Push("blank_" A_Index)
        }

        for (data in dataRows) {
            obj := {}
            data := StrSplit(data, dataSeparator)
            for (header in headers) {
                obj.%header% := data[A_Index]
            }
            objArray.Push(obj)
        }

        return objArray

        /**
         * Función de JavaScript para tablas, devuelve una cadena con los datos del tipo solicitado,
         * separados por los delimitadores indicados.
         * * No devuelve valor si no hay datos que devolver.
         * @param {String} query Consulta para la selección de la tabla objetivo.
         * @param {String} dataType Tipo de dato: "th" (cabeceras), "td" (datos).
         * @param {String} rowSeparator (Opcional) Delimitador para las filas. Por defecto: Salto de línea.
         * @param {String} dataSeparator (Opcional) Delimitador para los datos de las filas. Por defecto: ';'.
         */
        js(query, dataType, rowSeparator := "\n", dataSeparator := ";") =>
            (
                'function TableToString(query, dataType, rowSeparator = "\n", dataSeparator = ";") 
                {
                    const table = document.querySelector(query);
                    if (!table) return;
                
                    const rows = table.querySelectorAll("tr");
                    let output = Array.from(rows).map(row => {
                        const cells = row.querySelectorAll(dataType);
                        if (!cells.length) return;
                        
                        return Array.from(cells)
                        .map(cell => (dataType==="th") ? 
                            cell.querySelector("a")?.innerHTML.trim().replaceAll(" ", "_") ?? cell.innerText.trim().replaceAll(" ", "_")
                            : cell.querySelector("a")?.innerHTML.trim() ?? cell.innerText.trim()) // Replace spaces in headers
                        .join(dataSeparator);
                    }).filter(Boolean); // elimina filas vacías

                    return output.join(rowSeparator);
                }
                TableToString(`'' query '`',`'' dataType '`',`'' rowSeparator '`',`'' dataSeparator '`')'
            )
    }

    /**
     * 
     * @param page 
     * @param queryInput 
     * @param value 
     * @returns {Array String}
     */
    SetValueWithNativeSetter(page, queryInput, value)
    {
        page.WaitForElement(queryInput)
        return page.Evaluate(js(queryInput, value))
        
        js(queryInput, value) =>
        (
            'function changeValue(input, value) {
                if (!input || !value) return;
                const nativeSetter = Object.getOwnPropertyDescriptor(
                    window.HTMLInputElement.prototype, "value").set;
                nativeSetter.call(input, value);
                input.dispatchEvent(new Event("input", { bubbles: true }));
            }

            changeValue(document.querySelector("' queryInput '"), "' value '")'
        )
    }

    /**
     * 
     * @param page 
     * @param queryUserInput 
     * @param queryPasswordInput 
     * @param queryLoginButton 
     * @param queryErrorOutput 
     * @param userName 
     * @param password 
     * @returns {Array String}
     */
    Login(page, queryUserInput, queryPasswordInput, queryLoginButton, queryErrorOutput, userName, password)
    {
        page.WaitForLoad()
        this.SetValueWithNativeSetter(page, queryUserInput, userName)
        this.SetValueWithNativeSetter(page, queryPasswordInput, password)
        return page.Evaluate(js(queryLoginButton, queryErrorOutput))

        js(queryLoginButton, queryErrorOutput) =>
        (
            '// Asume que las credenciales ya han sido introducidas
            function login(queryLoginButton, queryErrorOutput) {
                button = document.querySelector(queryLoginButton)
                if (!button) return false;
                button.click();

                if (document.querySelector(queryErrorOutput)) {
                    return false;
                }
                return true;
            }

            login("' queryLoginButton '","' queryErrorOutput '")'
        )
    }

    /**
     * Mata la instancia de Chrome.
     */
    exitHandler()
    {
        ;this.Kill()
    }
}
