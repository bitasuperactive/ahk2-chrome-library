#Requires AutoHotkey v2.0
#Include "ChromeBridge\ChromeV2.ahk"
#Include "..\Util\JsonParser.ahk"
#Include "..\Util\OrObject.ahk"
#SingleInstance Force



/**
 * JavaScript Wrapper para `ChromeV2.Page`. 
 * Proporciona métodos específicos para interactuar con elementos de la página
 * a través de JavaScript, entre otras utilidades.
 * @author bitasuperactive, DeepSeek (estructura)
 * @date 27/09/2026
 * @version 2.0.0
 * @warning Dependencias:
 * - ChromeV2.ahk
 * - JsonParser.ahk
 * - OrObject.ahk
 */
class JSWrapper extends ChromeV2.Page
{
    /** 
     * @private
	 * @type {ChromeV2} Administrador de Chrome.
     */
    _chrome := unset ;

    /** 
     * @private
	 * @type {String} Url original.
     */
    _url := unset ;

    /**
     * @public
     * Crea una nueva instancia de `JSWrapper` que abre o vincula una página de
     * Chrome específica, identificada por su URL.
     * 
     * @warning JSWrapper asume que está en la URL correcta. Si has cacheado la instancia,
     * es recomendable utilizar `ChromeV2.Page._Navigation.GetUrl` para verificarla antes de manipular el DOM.
     * 
     * @param {ChromeV2} chromeManager Instancia del administrador de Chrome.
     * @param {String} url Enlace de la página a enlazar o abrir.
     * @param {String} matchMode (Opcional) Tipo de búsqueda para el enlace.
     * Puede ser: `exact`, `contains`, `startswith` o `regex`.
     * @param {Func} events (Opcional) Función a ejecutar cuando se reciba un mensaje de la página.
     */
    __New(chromeManager, url, matchMode := "exact", events := 0)
    {
        if !(chromeManager is ChromeV2)
            throw TypeError('Se esperaba una instancia de "' ChromeV2.Prototype.__Class
                '", pero se ha recibido: ' Type(chromeManager))

        this._chrome := chromeManager
        this._url := url

        if (!page := this._chrome.GetPageByURL(url, matchMode,, events))
            page := this._chrome.NewPage(url, events)
        super.__New(page.Url, page._callback)
    }
        
    /**
     * @public
     * Encapsula la ejecución de JavaScript entre `ChromeV2.Page.WaitForLoad()`.
     * @param {String} js Cadena de instrucciones JavaScript.
     * @returns {Object|0} Objeto de respuesta web con las propiedades: 
     * `className`, `description`, `objectId`, `subtype`, `type`, `value`.
     * @throws {Error} Si el código JavaScript ha generado una excepción.
     */
    WaitForEvaluate(js)
    {
        this.WaitForLoad()
        result := this.Evaluate(js)
        this.WaitForLoad()
        return result
    }

    /**
     * @public
     * Espera a que aparezca un elemento en el documento.
     * @param {String} selector Selector CSS.
     * @param {Integer} interval (Opcional) Intervalo en ms entre evaluaciones.
     * @param {Integer} timeout (Opcional) Límite en ms.
     * @returns {Boolean} `true` si el elemento aparece, `false` en su defecto.
     */
    WaitForElement(selector, interval := 100, timeout := 5000)
    {
        this.WaitForLoad()

        iterations := (timeout / interval)
        js := JSWrapper._Build(JSWrapper._JS.EXISTS, Map("selector", selector))

        Loop iterations {
            result := this.Evaluate(js)
            if (result is Map && result.Get("value", false))
                return true
            Sleep(interval)
        }
        return false
    }

    /**
     * @public
     * Restablece la navegación volviendo al url original.
     * Útil para garantizar el url antes de operar con el DOM.
     * @throws {Error} Si tras navegar al url original, la página te redirige automáticamente.
     * Esto suele ocurrir en urls de inicio de sesión cuando las credenciales estan cacheadas.
     */
    ResetNavigation() 
    {
        if (this.Navigation.GetUrl() != this._url) {
            this.Navigation.GoTo(this._url)
            actual := this.Navigation.GetUrl()
            if (actual != this._url)
                throw Error("La página web te ha redirigido automáticamente a: `"" actual "`"")
        }
    }

    /**
     * @public
     * Realiza un click en el elemento seleccionado por el selector CSS proporcionado.
     * @param {String} selector Selector del elemento, p. ej.: "#submit-button", ".nav-link".
     */
    Click(selector)
    {
        this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.CLICK, Map(
            "selector", selector
        )))
    }

    /**
     * @public
     * Introduce una cadena de texto en un input y dispara un evento "change"
     * para actualizar el formulario.
     * @note Si no funciona, utiliza `SetValueWithNativeSetter`.
     * @param {String} selector Selector del input, p. ej.: "#username".
     * @param {String} str Texto a introducir.
     */
    EditInputBox(selector, str)
    {
        this.WaitForElement(selector)
        this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.SET_VALUE, Map(
            "selector", selector,
            "value",    str
        )))
        this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.DISPATCH_CHANGE, Map(
            "selector", selector
        )))
    }

    /**
     * @public
     * Selecciona una opción en un `<select>` y dispara un evento "change".
     * @param {String} selector Selector del `<select>`.
     * @param {Integer} index Índice de la opción (base 0).
     */
    SelectListBox(selector, index)
    {
        this.WaitForElement(selector)
        this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.SET_INDEX, Map(
            "selector", selector,
            "index",    index
        )))
        this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.DISPATCH_CHANGE, Map(
            "selector", selector
        )))
    }

    /**
     * @public
     * Introduce un valor en un input usando el setter nativo de JavaScript,
     * garantizando que se disparen los eventos "input" y "change".
     * @param {String} selector Selector del input.
     * @param {String} value Valor a introducir.
     * @returns {Object|0} Respuesta del runtime de Chrome.
     */
    SetValueWithNativeSetter(selector, value)
    {
        this.WaitForElement(selector)
        return this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.NATIVE_SETTER, Map(
            "selector", selector,
            "value",    value
        )))
    }

    /**
     * @public
     * Realiza el proceso de login en una página web.
     * @warning La contraseña se introduce en texto plano.
     * @warning No soporta popups emergentes `prompt()`.
     * @param {String} selectorUserInput Selector del input de usuario.
     * @param {String} selectorPasswordInput Selector del input de contraseña.
     * @param {String} selectorLoginButton Selector del botón de login.
     * @param {String} selectorErrorOutput Selector del elemento de error de autenticación.
     * @param {String} userName Nombre de usuario.
     * @param {String} password Contraseña.
     * @returns {Boolean} `true` si el login fue correcto, `false` si hubo error.
     */
    Login(selectorUserInput, selectorPasswordInput, selectorLoginButton,
          selectorErrorOutput, userName, password)
    {
        this.WaitForElement(selectorLoginButton)
        this.SetValueWithNativeSetter(selectorUserInput, userName)
        this.SetValueWithNativeSetter(selectorPasswordInput, password)
        return this.WaitForEvaluate(JSWrapper._Build(JSWrapper._JS.LOGIN, Map(
            "loginButton", selectorLoginButton,
            "errorOutput", selectorErrorOutput
        )))
    }

    /**
     * @public
     * Extrae los datos de una tabla HTML y los devuelve como un array de
     * objetos ordenados.
     * @param {String} selector Selector de la tabla, p. ej.: "#data-table".
     * @returns {Array<OrObject>} Colección de objetos ordenados con los datos.
     */
    RetrieveTableData(selector)
    {
        this.WaitForElement(selector)

        rowSeparator  := "`n"
        dataSeparator := ";"

        ;// Recuperar cabeceras y datos
        headersEvaluation := this.Evaluate(JSWrapper._Build(JSWrapper._JS.TABLE_TO_STRING, Map(
            "selector",      selector,
            "dataType",      "th",
            "rowSeparator",  rowSeparator,
            "dataSeparator", dataSeparator
        )))
        dataEvaluation := this.Evaluate(JSWrapper._Build(JSWrapper._JS.TABLE_TO_STRING, Map(
            "selector",      selector,
            "dataType",      'td, th[scope="row"]',
            "rowSeparator",  rowSeparator,
            "dataSeparator", dataSeparator
        )))

        ;// Dividir en colecciones de cadenas
        headerRows := headersEvaluation.Has("value")
            ? StrSplit(headersEvaluation["value"], rowSeparator) : []
        dataRows := dataEvaluation.Has("value")
            ? StrSplit(dataEvaluation["value"], rowSeparator) : []

        if (!headerRows.Has(1) && !dataRows.Has(1))
            return []

        ;// Si no hay cabeceras, crearlas con nombres genéricos
        headers := []
        if (headerRows.Has(1)) {
            headers := StrSplit(headerRows[1], dataSeparator)
        } else {
            rowLength := StrSplit(dataRows[1], dataSeparator).Length
            Loop rowLength
                headers.Push("blank_" A_Index)
        }

        objArray := []
        for (data in dataRows) {
            obj := OrObject()
            data := StrSplit(data, dataSeparator)
            for (header in headers) {
                obj.%header% := data[A_Index]
            }
            objArray.Push(obj)
        }
        return objArray
    }

    /**
     * @private
     * Sustituye los marcadores `{nombre}` de una plantilla JavaScript por
     * literales JS válidos generados a partir de los valores proporcionados.
     * @param {String} template Plantilla JS con marcadores `{nombre}`.
     * @param {Map} params Mapa de `nombre => valor` para sustituir.
     * @returns {String} Plantilla renderizada lista para `Evaluate`/`WaitForEvaluate`.
     */
    static _Build(template, params)
    {
        if not params is Map
            throw TypeError("Se esperaba un Map, pero se ha recibido: " Type(params))
        for key, val in params
            template := StrReplace(template, "{" key "}", JSWrapper._Encode(val))
        return template
    }

    /**
     * @private
     * Codifica un valor como literal JavaScript válido.
     * @param {Any} val Valor a codificar.
     * @returns {String} Literal JS.
     */
    static _Encode(val) => SubStr(JsonParser.Stringify([val], 0), 2, -1) ;


    /**
     * @private
     * @class _JS
     * @brief Plantillas de JavaScript parametrizadas.
     *
     * Contrato de sustitución de marcadores `{nombre}`:
     * - Los marcadores cuyo valor sea **String** se sustituyen por un literal JSON
     *   (comillas dobles incluidas, con escapes de `"`, `\`, saltos de línea, etc.).
     *   Por eso NUNCA deben ir rodeados de comillas en la plantilla.
     * - Los marcadores cuyo valor sea **Integer** (p. ej. `{index}`) se insertan
     *   en crudo, sin comillas.
     *
     * Convenciones de escritura de las plantillas:
     * - El delimitador de cadena AHK es la comilla simple (`'...'`).
     * - Toda comilla dentro del propio JavaScript debe ser **doble** (`"..."`),
     *   para no colisionar con el delimitador de AHK.
     * - No incluir comentarios ni indentación externa: el snippet se envía tal cual
     *   a `Runtime.evaluate`.
     */
    class _JS
    {
        /**
         * @private
         * Comprueba si el selector coincide con al menos un elemento del DOM.
         *
         * Marcadores:
         * - `selector` {String} Selector CSS a comprobar.
         *
         * Devuelve `true` si existe, `false` en caso contrario.
         */
        static EXISTS =>
        (
            '
            !!document.querySelector({selector})
            '
        ) ;

        /**
         * @private
         * Hace click sobre el primer elemento que coincide con el selector.
         *
         * Marcadores:
         * - `selector` {String} Selector CSS del elemento a pulsar.
         *
         * Devuelve `void`.
         */
        static CLICK =>
        (
            '
            document.querySelector({selector}).click()
            '
        ) ;

        /**
         * @private
         * Asigna un valor directamente a la propiedad `value` del elemento.
         * No dispara eventos; para frameworks reactivos usar `NATIVE_SETTER`.
         *
         * Marcadores:
         * - `selector` {String} Selector CSS del input.
         * - `value`    {String} Valor a asignar.
         *
         * Devuelve el valor asignado.
         */
        static SET_VALUE =>
        (
            '
            document.querySelector({selector}).value = {value}
            '
        ) ;

        /**
         * @private
         * Selecciona una opción de un `<select>` por su índice.
         * No dispara eventos; para registrar el cambio usar `DISPATCH_CHANGE`.
         *
         * Marcadores:
         * - `selector` {String}  Selector CSS del `<select>`.
         * - `index`    {Integer} Índice de la opción (0-based).
         *
         * Devuelve el índice asignado.
         */
        static SET_INDEX =>
        (
            '
            document.querySelector({selector}).selectedIndex = {index}
            '
        ) ;

        /**
         * @private
         * Dispara el evento `change` sobre el elemento indicado.
         * Necesario para notificar a los formularios de que el valor ha cambiado.
         *
         * Marcadores:
         * - `selector` {String} Selector CSS del elemento modificado.
         *
         * Devuelve `true`.
         */
        static DISPATCH_CHANGE =>
        (
            '
            document.querySelector({selector}).dispatchEvent(new Event("change", { bubbles: true }))
            '
        ) ;

        /**
         * @private
         * Introduce un valor en un `<input>` usando el setter nativo de
         * `HTMLInputElement` y dispara los eventos `input` y `change`.
         *
         * @note Necesario para frameworks reactivos (React, Vue, etc.) que
         * interceptan las asignaciones directas a `.value` y no reaccionan a
         * `SET_VALUE`.
         *
         * Marcadores:
         * - `selector` {String} Selector CSS del input.
         * - `value`    {String} Valor a introducir.
         *
         * Devuelve `void`.
         */
        static NATIVE_SETTER =>
        (
            '
            function changeValue(input, value) {
                if (!input || !value) return;
                const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
                nativeSetter.call(input, value);
                input.dispatchEvent(new Event("input", { bubbles: true }));
            }

            changeValue(document.querySelector({selector}), {value})
            '
        ) ;

        /**
         * @private
         * Pulsa el botón de login y comprueba si el selector de error sigue
         * presente tras el click.
         *
         * @warning Asume que las credenciales ya han sido introducidas en el
         * formulario.
         *
         * Marcadores:
         * - `loginButton` {String} Selector CSS del botón de login.
         * - `errorOutput` {String} Selector CSS del elemento de error.
         *
         * Devuelve `true` si el login se ha realizado correctamente
         * (no aparece el elemento de error) o `false` en caso contrario.
         */
        static LOGIN =>
        (
            '
            function login(buttonSel, errorSel) {
                const button = document.querySelector(buttonSel);
                if (!button) return false;
                button.click();
                return !document.querySelector(errorSel);
            }

            login({loginButton}, {errorOutput})
            '
        ) ;

        /**
         * @private
         * Serializa una tabla HTML a una cadena plana usando separadores.
         *
         * @note La rama de normalización de cabeceras (`replaceAll(" ", "_")`)
         * solo se activa cuando `dataType` es exactamente `"th"`. Para selectores
         * mixtos (p. ej. `"td, th[scope='row']"`) las celdas se tratan como datos.
         *
         * @note Las celdas que contienen un `<a>` usan su `innerHTML`; el resto,
         * su `innerText`.
         *
         * Marcadores:
         * - `selector`       {String} Selector CSS de la tabla.
         * - `dataType`       {String} Selector CSS de las celdas a extraer
         *                             (habitualmente `"th"`, `"td"` o
         *                             `"td, th[scope='row']"`).
         * - `rowSeparator`   {String} Separador entre filas.
         * - `dataSeparator`  {String} Separador entre celdas.
         *
         * Devuelve un String con las filas unidas por `rowSeparator` y las celdas
         * por `dataSeparator`; cadena vacía si la tabla no existe.
         */
        static TABLE_TO_STRING =>
        (
            '
            function TableToString(selector, dataType, rowSeparator, dataSeparator) {
                const table = document.querySelector(selector);
                if (!table) return;
                const rows = table.querySelectorAll("tr");
                const output = Array.from(rows).map(row => {
                    const cells = row.querySelectorAll(dataType);
                    if (!cells.length) return;
                    return Array.from(cells)
                        .map(cell => (dataType === "th")
                            ? (cell.querySelector("a")?.innerHTML.trim().replaceAll(" ", "_")
                                ?? cell.innerText.trim().replaceAll(" ", "_"))
                            : (cell.querySelector("a")?.innerHTML.trim()
                                ?? cell.innerText.trim()))
                        .join(dataSeparator);
                }).filter(Boolean);
                return output.join(rowSeparator);
            }

            TableToString({selector}, {dataType}, {rowSeparator}, {dataSeparator})
            '
        ) ;
    } ;
}