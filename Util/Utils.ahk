#Requires AutoHotkey v2.0

/************************************************************************
 * @brief Funciones de utilidad general.
 * @author bitasuperactive
 * @date 26/12/2025
 * @version 1.0.2
 * @see https://github.com/bitasuperactive/ahk2-excel-library/blob/master/Util/Utils.ahk
 ***********************************************************************/
class Utils
{
    /**
     * @public
     * Código para la opción de mostrar los cuadros de mensaje por encima
     * del resto de ventanas.
     * @returns {String}
     */
    static MSGBOX_TOPMOST_OPT => "262144" ;
    
    /**
     * Envuelve todas las funciones de un objeto (instancia) con un proxy.
     * @param {Object} obj Instancia de clase objetivo.
     * @param {Func<Func, params*>} proxy Función proxy que recibe la función original
     * y sus parámetros. Debe devolver el resultado de la función original.
     */
    static ProxyObjFuncs(obj, proxy)
    {
        if (!IsObject(obj) || Type(obj) = "ComObject")
            throw TypeError("Se esperaba un objeto AHK, pero se ha recibido: " Type(obj))
        if !(proxy is Func)
            throw TypeError("Se esperaba una función, pero se ha recibido: " Type(proxy))
        if (proxy.__Class = "Closure")
            throw ValueError("La función proxy no puede ser un lambda.")
        if (!proxy.IsVariadic || proxy.MinParams < 1)
            throw ValueError("La función proxy debe ser variádica y definir 1 parámetro obligatorio que será la función a ejecutar.")

        for name in this.ObjOwnFuncs(obj) {
            ;// Evitar recursión infinita
            if (InStr(proxy.Name, name))
                continue
            
            originalFun := obj.%name%
            obj.DefineProp(name, { 
                Call: __delegate(originalFun, proxy)
            })
        }


        ;// Nuevo marco para clonar las variables
        __delegate(originalFun, proxy)
        {
            return (self, p*) => proxy.Call(self, originalFun, p*)
        }
    }

    /**
     * @public
     * Escapa el libro de trabajo activo de Excel. Útil cuando el usuario 
     * está editando una celda y se intenta acceder a la interfaz COM de Excel.
     */
    static EscapeExcelEditMode()
    {
        activeWinHwnd := WinGetID("A")
        activeWbHwnd := WinGetID("ahk_class XLMAIN") ; Última ventana activa de Excel
        WinActivate(activeWbHwnd)
        WinWaitActive(activeWbHwnd,, 2)
        Send("{Escape}")
        WinActivate(activeWinHwnd)
    }

    /**
     * @public
     * Busca un valor exacto en una colección.
     * 
     * @note Pensado para tipos primitivos.
     * 
     * @param {Array} arr Colección a evaluar.
     * @param {Any} val Valor buscado.
     * @returns {Integer} Índice del elemento encontrado, o 0 si no lo encuentra.
     */
    static ArrHasVal(arr, val)
    {
        if (Type(arr) != "Array")
            arr := [arr]
        
        for v in arr {
            if (v == val)
                return A_Index
        }
        return 0
    }

    /**
     * @public
     * Divide el nombre de un archivo en nombre y extensión.
     * @param {String} filename Nombre del archivo.
     * @returns {Array<String>} Colección con el nombre en la primera posición
     * y la extensión en la segunda (incluyendo el punto).
     */
    static StrSplitExtension(filename)
    {
        if (Type(filename) != "String")
            throw TypeError("Se esperaba un String, pero se ha recibido: " Type(filename))
        
        dotPos := InStr(filename, '.',, -1)
        if (dotPos = 0)
            return [filename, ""]

        name := SubStr(filename, 1, dotPos - 1)
        ext := SubStr(filename, dotPos)
        return [name, ext]
    }

    /**
     * @public
     * Obtiene los nombres de todas las funciones de una instancia de clase.
     * Omite las meta-funciones.
     * @param {Object} obj Objeto fuente.
     * @returns {Array<String>} Colección con los nombres de las funciones 
     * de la instancia.
     */
    static ObjOwnFuncs(obj)
    {
        if (!IsObject(obj) || Type(obj) = "ComObject")
            throw TypeError("El parámetro introducido no es un objeto AHK.")

        funcs := []
        baseObj := obj
        Loop {
            for name in ObjOwnProps(baseObj) {
                if (name = "__Init" 
                    || name = "__New"
                    || !obj.HasMethod(name) 
                    || !(obj.%name% is Func) 
                    || this.ArrHasVal(funcs, name))
                    continue
                
                funcs.Push(name)
            }
            baseObj := baseObj.Base
        } until (baseObj.__Class = "Object")

        return funcs
    }

    /**
     * @public
     * Valida que una instancia de clase sea hija de otra clase padre.
     * @param {Object} childObj Instancia de la clase hijo.
     * @param {Class} parentClass Clase padre.
     * @returns {Boolean} Verdadero si el objeto pertenece a la clase padre, 
     * falso en su defecto.
     */
    static ValidateInheritance(childObj, parentClass) 
    {
        if (!IsObject(childObj))
            throw TypeError("Se esperaba un objeto, pero se ha recibido: " Type(childObj))
        if (Type(parentClass) != "Class")
            throw TypeError("Se esperaba una clase, pero se ha recibido: " Type(parentClass))
        
        return InStr(this.GetPrototypeChain(childObj), parentClass.Prototype.__Class)
    }

    /**
     * @public
     * Valida que una clase sea hija de otra clase padre.
     * @param {Class} childClass Clase hijo.
     * @param {Class} parentClass Clase padre.
     * @returns {Boolean} Verdadero si la clase hija hereda de la clase padre,
     * Falso en su defecto.
     */
    static ValidateInheritanceClass(childClass, parentClass)
    {
        if (Type(childClass) != "Class")
            throw TypeError("Se esperaba una clase, pero se ha recibido: " Type(childClass))
        if (Type(parentClass) != "Class")
            throw TypeError("Se esperaba una clase, pero se ha recibido: " Type(parentClass))

        return InStr(childClass.Prototype.__Class, parentClass.Prototype.__Class)
    }

    /**
     * @public
     * Obtiene la cadena de herencia del elemento.
     * @param {Any} item Cualquier cosa.
     * @returns {String} Cadena de herencia separada por puntos.
     * @author GroggyOtter
     */
    static GetPrototypeChain(item) 
    {
        chain := ""                                 ; String to return with full prototype chain
        loop                                        ; Loop through the item
            item := item.Base                       ; Update the current item to the class it came from
            , chain := item.__Class '.' chain       ; Add the next class to the start of the chain
        Until item.__Class = "Any"                  ; Stop looping when the Any class is reached
        Return SubStr(chain, 1, -1)                 ; Trim the extra '.' separator from the end of the string
    }

    /**
     * @public
     * Elimina las tildes de una cadena de caracteres.
     * @param {String} str Cadena de caracteres objetivo.
     * @returns {String} Cadena de caracteres normalizada.
     * @author ChatGPT
     */
    static RemoveDiacritics(str)
    {
        if (Type(str) != "String")
            throw TypeError("Se esperaba un String pero se ha recibido: " Type(str))

        static accents := Map(
            "á","a","é","e","í","i","ó","o","ú","u","ü","u","ñ","n",
            "Á","A","É","E","Í","I","Ó","O","Ú","U","Ü","U","Ñ","N"
        )
        for k, v in accents
            str := StrReplace(str, k, v)
        return str
    }

    /**
     * @public
     * Transforma una colección de cadenas de caracteres en una sola cadena lista para mostrar al usuario.
     * @param {Array<String>} arr Colección de cadenas objetivo.
     * @returns {String} Cadena de caracteres con los valores separados por comas y finalizada en punto.
     */
    static ArrayToString(arr)
    {
        if (Type(arr) != "Array")
            arr := [arr]
        if (arr.Length = 0)
            return ""
        if (Type(arr[1]) != "String")
            throw TypeError("Los valores del Array deben ser de tipo String, pero contiene: " Type(arr[1]))
        
        str := ""
        for val in arr {
            append := (A_Index = arr.Length) ? "." : ", "
            str .= val append
        }
        return str
    }

    /**
     * @public
     * Mide el tiempo de ejecución de una función en segundos.
     * @param {Func} fun Función objetivo.
     * @param {Any} params Cualesquiera parámetros para la función.
     * @returns {Integer} Tiempo de ejecución en segundos.
     */
    static MeasureExecutionTime(fun, params*) 
    {
        if !(fun is Func)
            throw Error("El tipo " Type(fun) " no es una función válida.")
        
        start := A_TickCount
        fun.Call(params*)
        end := A_TickCount
        return ((end - start) / 1000)
    }
}