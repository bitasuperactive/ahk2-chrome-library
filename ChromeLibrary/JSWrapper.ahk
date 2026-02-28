#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "ChromeBridge\ChromeV2.ahk"
#Include "..\Util\ProcessWMI.ahk"
#Include "..\Util\OrObject.ahk"



;test()

/** @internal */
test() {
    chromeManager := ChromeV2(,, ProfilePath := "C:\Temp\ChromeDebug")
    loginPage := JSWrapper(chromeManager, "https://the-internet.herokuapp.com/login")
    blankPages := chromeManager.FindPages({url: "chrome://newtab/"}, matchMode := "exact")
    chromeManager.ClosePage(blankPages[1], "exact")
    result := loginPage.Login(selectorUserInput := "#username"
        , selectorPasswordInput := "#password"
        , selectorLoginButton := "button[type='submit']"
        , selectorErrorOutput := "#flash.error"
        , userName := "tomsmith"
        , password := "SuperSecretPassword!"
    )
    if (result)
        MsgBox("Login exitoso.")
    else
        MsgBox("Error de autenticación.")

    loginPage.WaitForEvaluate('document.querySelector("#content > div > a > i").click()')
}



/**
 * JavaScript Wrapper para `ChromeV2.Page`, proporciona métodos específicos para interactuar 
 * con elementos de la página a través de JavaScript.
 * 
 * Páginas web de ejemplo para testear automatizaciones:
 *  - https://the-internet.herokuapp.com/
 *  - https://www.saucedemo.com/
 * 
 * @author bitasuperactive
 * @date 27/02/2026
 * @version 1.0.0
 * @Warning Dependencias:
 * - ChromeV2.ahk
 * - ProcessWMI.ahk
 * - OrObject.ahk
 * @see https://github.com/bitasuperactive/ahk2-chrome-library/blob/master/ChromeLibrary/JSWrapper.ahk
 * @internal Documentación web: https://bitasuperactive.github.io/ahk2-chrome-library
 */
class JSWrapper extends ChromeV2.Page
{
    Chrome := unset ;

    /**
     * @public
     * Crea una nueva instancia de `JSWrapper` que abre o vincula una página de Chrome específica, identificada por su URL.
     * @note Controla el cierre manual o inesperado del proceso de Chrome lanzando un error.
     * @param {ChromeV2} chromeManager Instancia del administrador de Chrome.
     * @param {String} url Enlace de la página a enlazar o abrir.
     * @param {String} matchMode (Opcional) Tipo de búsqueda para el enlace. 
     * Puede ser: `exact`, `contains`, `startswith` o `regex`. Por defecto: `exact`.
     * @param {Func} events (Opcional) Función a ejecutar cuando se reciba un mensaje de la página: `msg => void`.
     */
    __New(chromeManager, url, matchMode := "exact", events := 0)
    {
        if !(chromeManager is ChromeV2)
            throw TypeError('Se esperaba una instancia de "' ChromeV2.Prototype.__Class '", pero se ha recibido: ' Type(chromeManager))
        this.Chrome := chromeManager
        if (!page := this.Chrome.GetPageByURL(url, matchMode,, events))
            page := this.Chrome.NewPage(url, events)
        super.__New(page.Url, page._callback)
        
        try {
            this._applicationWatcher := ProcessWMIWatcher(this.Chrome.ExeName, (caller, state) => this._OnChromeClosed(state))
        }
        catch Error as err {
            MsgBox("No ha sido posible establecer el escuchador del proceso de Google Chrome.`n`nError: " err.Message, "ERROR", 16)
        }
    }

    /**
     * @throws {Error} Si el proceso de Chrome se ha cerrado de manera inesperada.
     */
    _OnChromeClosed(state)
    {
        if (!state)
            throw Error("Chrome ha sido cerrado de manera inesperada.")
    }

    /**
     * @public
     * Realiza un click en el elemento seleccionado por el selector CSS proporcionado.
     * @param {String} selector Selector del elemento a hacer click, por ejemplo: "#submit-button", ".nav-link", etc.
     */
    Click(selector)
    {
        this.WaitForEvaluate('document.querySelector("' selector '").click()')
    }

    /**
     * @public
     * Introduce una cadena de texto en el elemento input seleccionado por el selector CSS proporcionado y dispara un evento "change" para actualizar el formulario.
     * @note Si no funciona, utilizar `SetValueWithNativeSetter` para asegurar que se disparen los eventos asociados al cambio de valor.
     * @param {String} selector Selector del elemento input a editar, por ejemplo: "#username", ".search-field", etc.
     * @param {String} str Cadena de texto a introducir en el elemento seleccionado.
     */
    EditInputBox(selector, str)
    {
        this.Evaluate('document.querySelector("' selector '").value = "' str '"')
        this.WaitForEvaluate('document.querySelector("' selector '").dispatchEvent(new Event("change", { bubbles: true }));') ; actualizar form
    }

    /**
     * @public
     * Selecciona una opción en un elemento select (lista desplegable) utilizando el índice de la opción y dispara un evento "change" para actualizar el formulario.
     * @param {String} selector Selector del elemento select a editar, por ejemplo: "#country-select", ".options-dropdown", etc.
     * @param {Integer} index Índice de la opción a seleccionar (comenzando desde 0).
     */
    SelectListBox(selector, index)
    {
        this.Evaluate('document.querySelector("' selector '").selectedIndex = ' index)
        this.WaitForEvaluate('document.querySelector("' selector '").dispatchEvent(new Event("change", { bubbles: true }));') ; actualizar form
    }

    /**
     * @public
     * Introduce un valor en un elemento input utilizando el setter nativo de JavaScript para asegurar que se disparen los eventos asociados al cambio de valor, como "input" o "change".
     * @param {String} selector Selector del elemento input a editar, por ejemplo: "#username", ".search-field", etc.
     * @param {String} value Valor a introducir en el elemento seleccionado.
     */
    SetValueWithNativeSetter(selector, value)
    {
        this.WaitForElement(selector)
        return this.Evaluate(js(selector, value))
        
        
        /**
         * @internal
         * Función de JavaScript para introducir un valor en un elemento input utilizando el setter nativo de JavaScript.
         * Esto asegura que se disparen los eventos asociados al cambio de valor, como "input" o "change", 
         * lo que puede ser necesario para que la página web reconozca el cambio y actualice su estado en consecuencia.
         */
        js(selector, value) =>
        (
            'function changeValue(input, value) {
                if (!input || !value) return;
                const nativeSetter = Object.getOwnPropertyDescriptor(
                    window.HTMLInputElement.prototype, "value").set;
                nativeSetter.call(input, value);
                input.dispatchEvent(new Event("input", { bubbles: true }));
            }

            changeValue(document.querySelector("' selector '"), "' value '")'
        )
    }

    /**
     * @public
     * Realiza el proceso de login en una página web introduciendo el nombre de usuario y contraseña en los campos correspondientes, 
     * haciendo click en el botón de login y verificando si se ha producido algún error de autenticación.
     * @warning La contraseña se introducirá en texto plano, por lo que se recomienda utilizar esta función solo en entornos controlados o de prueba.
     * @param {String} selectorUserInput Selector del campo de entrada del nombre de usuario, por ejemplo: "#username", ".user-field", etc.
     * @param {String} selectorPasswordInput Selector del campo de entrada de la contraseña, por ejemplo: "#password", ".pass-field", etc.
     * @param {String} selectorLoginButton Selector del botón de login a hacer click, por ejemplo: "#login-button", ".submit-btn", etc.
     * @param {String} selectorErrorOutput Selector del elemento que indica un error de autenticación, por ejemplo: "#error-message", ".login-error", etc.
     * @param {String} userName Nombre de usuario a introducir en el campo correspondiente.
     * @param {String} password Contraseña a introducir en el campo correspondiente.
     * @returns {Boolean} `true` si el login se ha realizado correctamente, o `false` si se ha producido un error de autenticación. 
     */
    Login(selectorUserInput, selectorPasswordInput, selectorLoginButton, selectorErrorOutput, userName, password)
    {
        this.WaitForLoad()
        this.SetValueWithNativeSetter(selectorUserInput, userName)
        this.SetValueWithNativeSetter(selectorPasswordInput, password)
        return this.Evaluate(js(selectorLoginButton, selectorErrorOutput))


        /**
         * @internal
         * Función de JavaScript para realizar el proceso de login en una página web. 
         * Hace click en el botón de login y verifica si se ha producido algún error de autenticación.
         * @warning Asume que las credenciales ya han sido introducidas en los campos correspondientes antes de llamar a esta función.
         * @returns {Boolean} `true` si el login se ha realizado correctamente, o `false` si se ha producido un error de autenticación.
         */
        js(selectorLoginButton, selectorErrorOutput) =>
        (
            '// Asume que las credenciales ya han sido introducidas
            function login(selectorLoginButton, selectorErrorOutput) {
                button = document.querySelector(selectorLoginButton)
                if (!button) return false;
                button.click();

                if (document.querySelector(selectorErrorOutput)) {
                    return false;
                }
                return true;
            }

            login("' selectorLoginButton '","' selectorErrorOutput '")'
        )
    }

    /**
     * @public
     * Extrae los datos de una tabla HTML y los devuelve como un array de objetos ordenados.
     * @param {String} selector Selector de la tabla a extraer, por ejemplo: "#data-table", ".info-table", etc.
     * @returns {Array<OrObject>} Colección de objetos ordenados con los datos de la tabla, 
     * donde cada objeto representa una fila y las propiedades corresponden a las cabeceras de la tabla. 
     * Si no hay cabeceras o estas contienen otros objetos como enlaces, se les asigna nombres genéricos como "blank_1", "blank_2", etc.
     */
    RetrieveTableData(selector)
    {
        this.WaitForLoad()
        rowSeparator := "`n"
        dataSeparator := ";"
        objArray := []
        
        ;// Recuperar cabeceras y datos
        headersEvaluation := this.Evaluate(js(selector, "th"))
        dataEvaluation := this.Evaluate(js(selector, 'td, th[scope="row"]'))

        ;// Dividir las respuestas en colecciones de cadenas
        headerRows := (headersEvaluation.Has("value")) ? StrSplit(headersEvaluation["value"], rowSeparator) : []
        dataRows := (dataEvaluation.Has("value")) ? StrSplit(dataEvaluation["value"], rowSeparator) : []

        if (!headerRows.Has(1) && !dataRows.Has(1)) {
            return []
        }

        ;// Si no hay cabeceras, crearlas con nombres genéricos
        headers := []
        if (headerRows.Has(1)) {
            headers := StrSplit(headerRows[1], dataSeparator)
        } else {
            rowLength := StrSplit(dataRows[1], dataSeparator).Length
            Loop rowLength
                headers.Push("blank_" A_Index)
        }

        for (data in dataRows) {
            obj := OrObject()
            data := StrSplit(data, dataSeparator)
            for (header in headers) {
                obj.%header% := data[A_Index]
            }
            objArray.Push(obj)
        }
        return objArray


        /**
         * @internal
         * Función de JavaScript para leer tablas HTML.
         * @returns {String} Cadena con los datos extraídos de la tabla, separados por los delimitadores indicados.
         * Por defecto, cada fila se separa por un salto de línea (`\n`) y cada dato dentro de la fila se separa por 
         * un punto y coma (`;`).
         */
        js(selector, dataType, rowSeparator := "\n", dataSeparator := ";") =>
            (
                'function TableToString(selector, dataType, rowSeparator = "\n", dataSeparator = ";") 
                {
                    const table = document.querySelector(selector);
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
                TableToString(`'' selector '`',`'' dataType '`',`'' rowSeparator '`',`'' dataSeparator '`')'
            )
    }
}
